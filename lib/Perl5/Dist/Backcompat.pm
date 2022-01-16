package Perl5::Dist::Backcompat;
use 5.14.0;
use warnings;
our $VERSION = '0.01';
use Carp qw( carp croak );
use Cwd qw( cwd );
#use Data::Dumper;$Data::Dumper::Indent=1;
use File::Copy qw( copy );
use File::Find qw( find );
use File::Spec;
use File::Temp qw( tempdir );
use Getopt::Long qw( GetOptions );
# From CPAN
use File::Copy::Recursive::Reduced qw( dircopy );
use Data::Dump qw( dd pp );

=head1 NAME

Perl5::Dist::Backcompat - Will changes to F<dist/> build on older C<perl>s?

=head1 SYNOPSIS

    my $params = {
        perl_workdir => '/path/to/git/checkout/of/perl',
        verbose => 1,
    };
    my $self = Perl5::Dist::Backcompat->new( $params );

=head1 PREREQUISITES

F<perl> 5.14.0 or newer, with the following modules installed from CPAN:

=over 4

=item * F<Data::Dump>

=item * F<File::Copy::Recursive::Reduced>

=back

=head1 PUBLIC METHODS

=head2 C<new()>

=over 4

=item * Purpose

Perl5::Dist::Backcompat constructor.

=item * Arguments

    my $self = Perl5::Dist::Backcompat->new( $params );

Single hash reference.

=item * Return Value

Perl5::Dist::Backcompat object.

=item * Comment

=back

=cut

sub new {
    my ($class, $params) = @_;
    if (defined $params and ref($params) ne 'HASH') {
        croak "Argument supplied to constructor must be hashref";
    }
    my %valid_params = map {$_ => 1} qw(
        verbose
        host
        path_to_perls
        perl_workdir
        tarball_dir
    );
    my @invalid_params = ();
    for my $p (keys %$params) {
        push @invalid_params, $p unless $valid_params{$p};
    }
    if (@invalid_params) {
        my $msg = "Constructor parameter(s) @invalid_params not valid";
        croak $msg;
    }
    croak "Must supply value for 'perl_workdir'"
        unless $params->{perl_workdir};

    my $data = {};
    for my $p (keys %valid_params) {
        $data->{$p} = (defined $params->{$p}) ? $params->{$p} : '';
    }
    $data->{host} ||= 'dromedary.p5h.org';
    $data->{path_to_perls} ||= '/media/Tux/perls-t/bin';
    $data->{tarball_dir} ||= "$ENV{P5P_DIR}/dist-backcompat/tarballs";

    croak "Could not locate directory $data->{path_to_perls} for perl executables"
        unless -d $data->{path_to_perls};
    croak "Could not locate directory $data->{tarball_dir} for downloaded tarballs"
        unless -d $data->{tarball_dir};

    return bless $data, $class;
}

=head2 C<init()>

=over 4

=item * Purpose

Guarantee that we can find the F<perl> executables we'll be using; the F<git>
checkout of the core distribution; metadata files and loading of data
therefrom.

=item * Arguments

    $self->init();

None; all data needed is found within the object.

=item * Return Value

Returns the object itself.

=item * Comment

=back

=cut

sub init {
    # From here on, we assume we're in author's directory on dromedary.
    my $self = shift;

    my $currdir = cwd();
    chdir $self->{perl_workdir}
        or croak "Unable to change to $self->{perl_workdir}";

    my $describe = `git describe`;
    chomp($describe);
    croak "Unable to get value for 'git describe'"
        unless $describe;
    $self->{describe} = $describe;
    chdir $currdir or croak "Unable to change back to starting directory";

    my $manifest = File::Spec->catfile($self->{perl_workdir}, 'MANIFEST');
    croak "Could not locate $manifest" unless -f $manifest;
    $self->{manifest} = $manifest;

    my $maint_file = File::Spec->catfile($self->{perl_workdir}, 'Porting', 'Maintainers.pl');
    require $maint_file;   # to get %Modules in package Maintainers
    $self->{maint_file} = $maint_file;

    my $manilib_file = File::Spec->catfile($self->{perl_workdir}, 'Porting', 'manifest_lib.pl');
    require $manilib_file; # to get function sort_manifest()
    $self->{manilib_file} = $manilib_file;

    my %distmodules = ();
    for my $m (keys %Maintainers::Modules) {
        if ($Maintainers::Modules{$m}{FILES} =~ m{dist/}) {
            $distmodules{$m} = $Maintainers::Modules{$m};
        }
    }

    # Sanity checks; all modules under dist/ should be blead-upstream and have P5P
    # as maintainer.
    _sanity_check(\%distmodules, $self->{describe}, $self->{verbose});
    $self->{distmodules} = \%distmodules;

    my $metadata_file = File::Spec->catfile(
        '.', 'etc', 'dist-backcompat-distro-metadata.txt');
    croak "Could not locate $metadata_file" unless -f $metadata_file;
    $self->{metadata_file} = $metadata_file;

    my %distro_metadata = ();

    open my $IN, '<', $metadata_file or croak "Unable to open $metadata_file for reading";
    while (my $l = <$IN>) {
        chomp $l;
        next if $l =~ m{^(\#|\s*$)};
        my @rowdata = split /\|/, $l;
        # Refine this later
        $distro_metadata{$rowdata[0]} = {
            minimum_perl_version => $rowdata[1] // '',
            needs_threads        => $rowdata[2] // '',
            cpan_makefile_pl     => $rowdata[3] // '',
        };
    }
    close $IN or die "Unable to close $metadata_file after reading: $!";
    $self->{distro_metadata} = \%distro_metadata;

    my $older_perls_file = File::Spec->catfile(
        '.', 'etc', 'dist-backcompat-older-perls.txt');
    croak "Could not locate $older_perls_file" unless -f $older_perls_file;
    $self->{older_perls_file} = $older_perls_file;

    return $self;
}

=head2 C<categorize_distros()>

=over 4

=item * Purpose

Categorize each F<dist/> distro in one of 4 categories.

=item * Arguments

    $self->categorize_distros();

None; all data needed is already within the object.

=item * Return Value

Returns the object.

=item * Comment

Current categorization procedure is very dubious.

=back

=cut

sub categorize_distros {
    my $self = shift;
    my %makefile_pl_status = ();

    for my $m (keys %{$self->{distmodules}}) {
        if (! exists $self->{distmodules}->{$m}{DISTRIBUTION}) {
            my ($distname) = $self->{distmodules}->{$m}{FILES} =~ m{^dist/(.*)/?$};
            $makefile_pl_status{$distname} = 'unreleased';
        }
    }

    # Second, identify those dist/ distros which have their own hard-coded
    # Makefile.PLs in the core distribution.  We'll call these 'native'.

    #my $manifest = File::Spec->catfile($dir, 'MANIFEST');
    my @sorted = read_manifest($self->{manifest});

    for my $f (@sorted) {
        next unless $f =~ m{^dist/};
        my $path = (split /\t+/, $f)[0];
        if ($path =~ m{/(.*?)/Makefile\.PL$}) {
            my $distro = $1;
            $makefile_pl_status{$distro} = 'native'
                unless exists $makefile_pl_status{$distro};
        }
    }

    # Third, identify those dist/ distros whose Makefile.PL is generated during
    # Perl's own 'make' process.

    my $get_generated_makefiles = sub {
        my $pattern = qr{dist/(.*?)/Makefile\.PL$};
        if ( $File::Find::name =~ m{$pattern} ) {
            my $distro = $1;
            if (! exists $makefile_pl_status{$distro}) {
                $makefile_pl_status{$distro} = 'generated';
            }
        }
    };
    find(
        \&{$get_generated_makefiles},
        File::Spec->catdir($self->{perl_workdir}, 'dist' )
    );

    # Fourth, identify those dist/ distros whose Makefile.PLs must presumably be
    # obtained from CPAN.

    for my $d (sort keys %{$self->{distmodules}}) {
        next unless exists $self->{distmodules}->{$d}{FILES};
        my ($distname) = $self->{distmodules}->{$d}{FILES} =~ m{^dist/(.*)/?$};
        if (! exists $makefile_pl_status{$distname}) {
            $makefile_pl_status{$distname} = 'cpan';
        }
    }

    # Check tarballs we have on disk to see whether they contain a
    # Makefile.PL.
    # $ pwd
    # /home/jkeenan/learn/perl/p5p/dist-backcompat/tarballs/authors/id
    # $ ls . | head -n 5
    # Attribute-Handlers-0.99.tar.gz
    # autouse-1.11.tar.gz
    # base-2.23.tar.gz
    # Carp-1.50.tar.gz
    # constant-1.33.tar.gz

    $self->{makefile_pl_status} = \%makefile_pl_status;
    return $self;
}

=head2 C<show_makefile_pl_status>

=over 4

=item * Purpose

Display a chart listing F<dist/> distros in one column and the status of their respective F<Makefile.PL>s in the second column.

=item * Arguments

    $self->show_makefile_pl_status();

None; this method simply displays data already present in the object.

=item * Return Value

Returns a true value when complete.

=item * Comment

Does nothing unless a true value for C<verbose> was passed to C<new()>.

=back

=cut

sub show_makefile_pl_status {
    my $self = shift;
    my %counts;
    for my $module (sort keys %{$self->{makefile_pl_status}}) {
        $counts{$self->{makefile_pl_status}->{$module}}++;
    }
    if ($self->{verbose}) {
        for my $k (sort keys %counts) {
            printf "  %-18s%4s\n" => ($k, $counts{$k});
        }
        say '';
        printf "%-24s%-12s\n" => ('Distribution', 'Status');
        printf "%-24s%-12s\n" => ('------------', '------');
        for my $module (sort keys %{$self->{makefile_pl_status}}) {
            printf "%-24s%-12s\n" => ($module, $self->{makefile_pl_status}->{$module});
        }
    }
    return 1;
}

=head2 C<get_distros_for_testing()>

=over 4

=item * Purpose

Assemble the list of F<dist/> distros which the program will actually test
against older F<perl>s.

=item * Arguments

    my @distros_for_testing = $self->get_distros_for_testing( [ @distros_requested ] );

Single arrayref, optional (though recommended).  If no arrayref is provided,
then the program will test I<all> F<dist/> distros I<except> those whose
"Makefile.PL status" is C<unreleased>.

=item * Return Value

List holding distros to be tested.  (This is provided for readability of the
code, but the list will be stored within the object and subsequently
referenced therefrom.

=item * Comment

In a production program, the list of distros selected for testing may be
provided on the command-line and processed by C<Getopt::Long::GetOptions()>
within that program.  But it's only at this point that we need to add such a
list to the object.

=back

=cut

sub get_distros_for_testing {
    my ($self, $distros) = @_;
    if (defined $distros) {
        croak "Argument passed to get_distros_for_testing() must be arrayref"
            unless ref($distros) eq 'ARRAY';
    }
    else {
        $distros = [];
    }
    my @distros_for_testing = (scalar @{$distros})
        ? @{$distros}
        : sort grep { $self->{makefile_pl_status}->{$_} ne 'unreleased' }
            keys %{$self->{makefile_pl_status}};
    if ($self->{verbose}) {
        say "\nWill test ", scalar @distros_for_testing,
            " distros which have been presumably released to CPAN:";
        say "  $_" for @distros_for_testing;
    }
    $self->{distros_for_testing} = [ @distros_for_testing ];
    return @distros_for_testing;
}

=head2 C<validate_older_perls()>

=over 4

=item * Purpose

Validate the paths and executability of the older perl versions against which
we're going to test F<dist/> distros.

=item * Arguments

    my @perls = $self->validate_older_perls();

None; all necessary information is found within the object.

=item * Return Value

List holding older F<perl> executables against which distros will be tested.
(This is provided for readability of the code, but the list will be stored
within the object and subsequently referenced therefrom.

=back

=cut

sub validate_older_perls {
    my $self = shift;
    my @perllist = ();
    open my $IN1, '<', $self->{older_perls_file}
        or croak "Unable to open $self->{older_perls_file} for reading";
    while (my $l = <$IN1>) {
        chomp $l;
        next if $l =~ m{^(\#|\s*$)};
        push @perllist, $l;
    }
    close $IN1
        or croak "Unable to close $self->{older_perls_file} after reading";

    my @perls = ();

    for my $p (@perllist) {
        say "Locating $p executable ..." if $self->{verbose};
        my $rv;
        my $path_to_perl = File::Spec->catfile($self->{path_to_perls}, $p);
        warn "Could not locate $path_to_perl" unless -e $path_to_perl;
        $rv = system(qq| $path_to_perl -v 1>/dev/null 2>&1 |);
        warn "Could not execute perl -v with $path_to_perl" if $rv;

        my ($major, $minor, $patch) = $p =~ m{^perl(5)\.(\d+)\.(\d+)$};
        my $canon = sprintf "%s.%03d%03d" => ($major, $minor, $patch);

        push @perls, {
            version => $p,
            path => $path_to_perl,
            canon => $canon,
        };
    }
    $self->{perls} = [ @perls ];
    return @perls;
}

=head2 C<test_distros_against_older_perls()>

=over 4

=item * Purpose

Test a given F<dist/> distro against each of the older F<perl>s against which
it is eligible to be tested.

=item * Arguments

    $self->test_distros_against_older_perls('/path/to/debugging/directory');

String holding absolute path to an already created directory to which files
can be written for later study and debugging.  That directory I<may> be
created by C<File::Temp:::tempdir()>, but it should I<not> be created with C<(
CLEANUP => 1)>; the user should manually remove this directory after analysis
is complete.

=item * Return Value

Returns the object itself.

=item * Comment

The method will loop over the selected distros, calling
C<test_one_distro_against_older_perls()> against each.

=back

=cut

sub test_distros_against_older_perls {
    my ($self, $debugdir) = @_;
    # $debugdir will be explicitly user-created to hold the results of
    # testing.

    # A program using Perl5::Dist::Backcompat won't need it until now. So even
    # if we feed that directory to the program via GetOptions, it doesn't need
    # to go into the constructor.  It may be a tempdir but should almost
    # certainly NOT be set to get automatically cleaned up at program
    # conclusion (otherwise, where would you look for the results?).

    croak "Unable to locate $debugdir" unless -d $debugdir;
    $self->{debugdir} = $debugdir;

    # Calculations WILL, however, be done in a true tempdir.  We'll create
    # subdirs and files underneath that tempdir.  We'll cd to that tempdir but
    # come back to where we started before this method exits.
    # $self->{temp_top_dir} will be the conceptual equivalent of the top-level
    # directory in the Perl 5 distribution.  Hence, underneath it we'll create
    # the equivalents of the F<dist/Distro-A>, F<dist/Distro-B>, etc., and
    # F<t/> directories.
    $self->{currdir} = cwd();
    $self->{temp_top_dir} = tempdir( CLEANUP => 1 );
    my %results = ();

    chdir $self->{temp_top_dir} or croak "Unable to change to tempdir $self->{temp_top_dir}";

    # Create a 't/' directory underneath the temp_top_dir
    my $temp_t_dir = File::Spec->catdir($self->{temp_top_dir}, 't');
    mkdir $temp_t_dir or croak "Unable to mkdir $temp_t_dir";
    $self->{temp_t_dir} = $temp_t_dir;

    # Several of the F<dist/> distros need F<t/test.pl> for their tests; copy
    # it into position once only.
    my $testpl = File::Spec->catfile($self->{perl_workdir}, 't', 'test.pl');
    croak "Could not locate $testpl" unless -f $testpl;
    copy $testpl => $self->{temp_t_dir} or croak "Unable to copy $testpl";

    # Create a 'dist/' directory underneath the temp_top_dir
    my $temp_dist_dir = File::Spec->catdir($self->{temp_top_dir}, 'dist');
    mkdir $temp_dist_dir or croak "Unable to mkdir $temp_dist_dir";
    $self->{temp_dist_dir} = $temp_dist_dir;

    for my $d (@{$self->{distros_for_testing}}) {
        my $this_result = $self->test_one_distro_against_older_perls($d);
        $results{$d} = $this_result;
    }

    chdir $self->{currdir}
        or croak "Unable to change back to starting directory $self->{currdir}";

    $self->{results} = { %results };
    return $self;

    # temp_top_dir should go out of scope here (though its path and those of
    # temp_t_dir and temp_dist_dir will still be in the object)
}

=head2 C<print_distro_summaries()>

=over 4

=item * Purpose

Print on F<STDOUT>:

=over 4

=item 1

A list of the F<debugdir/Some-Distro.summary.txt> files created for each
tested distro (each file containing a summary of the results for that distro
against each designated F<perl> executable. Example:

    Summaries
    ---------
    Attribute-Handlers      /tmp/29LsgNfjVb/Attribute-Handlers.summary.txt
    Carp                    /tmp/29LsgNfjVb/Carp.summary.txt
    Data-Dumper             /tmp/29LsgNfjVb/Data-Dumper.summary.txt
    ...
    threads                 /tmp/29LsgNfjVb/threads.summary.txt
    threads-shared          /tmp/29LsgNfjVb/threads-shared.summary.txt

=item 2

A concatenation of all those files.

=back

=item * Arguments

To simply list the summary files:

    $self->print_distro_summaries();

To list the summary files and concatenate their content:

    $self->print_distro_summaries( {cat_summaries => 1} );

=item * Return Value

Returns true value upon success.

=item * Comment

You'll probably want to redirect or F<tee> F<STDOUT> to a file for further
study.

=back

=cut

sub print_distro_summaries {
    my ($self, $args) = @_;
    if (! defined $args) { $args = {}; }
    else {
        croak "Argument to print_distro_summaries must be hashref"
            unless ref($args) eq 'HASH';
    }

    say "\nSummaries";
    say '-' x 9;
    for my $d (sort keys %{$self->{results}}) {
        $self->print_distro_summary($d);
    }

    if ($args->{cat_summaries}) {
        say "\nOverall (at $self->{describe}):";
        for my $d (sort keys %{$self->{results}}) {
            say "\n$d";
            dd $self->{results}->{$d};
        }
    }
    return 1;
}

=head1 INTERNAL METHODS

The following methods use the Perl5::Dist::Backcompat object but are called
from within the public methods.

=cut

=head2 C<test_one_distro_against_older_perls()>

=over 4

=item * Purpose

Test one selected F<dist/> distribution against the list of older F<perl>s.

=item * Arguments

Single string holding the name of the distro in C<Some-Distro> format.

=item * Return Value

Hash reference with one element for each F<perl> executable selected:

    {
    "5.006002" => { a => "perl5.6.2",  configure => 1, make => 0, test => undef },
    "5.008009" => { a => "perl5.8.9",  configure => 1, make => 0, test => undef },
    "5.010001" => { a => "perl5.10.1", configure => 1, make => 0, test => undef },
    ...
    "5.034000" => { a => "perl5.34.0", configure => 1, make => 1, test => 1 },
    }

The value of each element is a hashref with elements keyed as follows:

=over 4

=item * C<a>

Perl version in the spelling used in the default value for C<path_to_perls>.

=item * C<configure>

The result of calling F<perl Makefile.PL>: C<1> for success; C<0> for failure;
C<undef> for not attempted.

=item * C<make>

The result of calling F<make>: same meaning as above.

=item * C<make test>

The result of calling F<make test>: same meaning as above.

=back

=item * Comment

=back

=cut

sub test_one_distro_against_older_perls {
    my ($self, $d) = @_;
    say "Testing $d ..." if $self->{verbose};
    my $this_result = {};

    my $source_dir = File::Spec->catdir($self->{perl_workdir}, 'dist', $d);
    my $this_tempdir  = File::Spec->catdir($self->{temp_dist_dir}, $d);
    mkdir $this_tempdir or croak "Unable to mkdir $this_tempdir";
    dircopy($source_dir, $this_tempdir)
        or croak "Unable to copy $source_dir to $this_tempdir";

    chdir $this_tempdir or croak "Unable to chdir to tempdir for dist/$d";
    say "  Now in $this_tempdir ..." if $self->{verbose};
    #system(qq| find . -type f |) and croak;

    THIS_PERL: for my $p (@{$self->{perls}}) {
        $this_result->{$p->{canon}}{a} = $p->{version};
        # Skip this perl version if (a) distro has a specified
        # 'minimum_perl_version' and (b) that minimum version is greater than
        # the current perl we're running.
        if (
            (
                $self->{distro_metadata}->{$d}{minimum_perl_version}
                    and
                $self->{distro_metadata}->{$d}{minimum_perl_version} >= $p->{canon}
            )
#                Since we're currently using threaded perls for this
#                process, the following condition is not pertinent.  But we'll
#                retain it here commented out for possible future use.
#
#                or
#            (
#                $self->{distro_metadata}->{$d}{needs_threads}
#            )
        ) {
            $this_result->{$p->{canon}}{configure} = undef;
            $this_result->{$p->{canon}}{make} = undef;
            $this_result->{$p->{canon}}{test} = undef;
            next THIS_PERL;
        }
        my $f = join '.' => ($d, $p->{version}, 'txt');
        my $debugfile = File::Spec->catfile($self->{debugdir}, $f);
        if ($self->{verbose}) {
            say "Testing $d with $p->{canon} ($p->{version}); see $debugfile";
        }
        my $rv;
        $rv = system(qq| $p->{path} Makefile.PL > $debugfile 2>&1 |)
            and say STDERR "  FAIL: $d: $p->{canon}: Makefile.PL";
        $this_result->{$p->{canon}}{configure} = $rv ? 0 : 1; undef $rv;
        unless ($this_result->{$p->{canon}}{configure}) {
            undef $this_result->{$p->{canon}}{make};
            undef $this_result->{$p->{canon}}{test};
            next THIS_PERL;
        }

        $rv = system(qq| make >> $debugfile 2>&1 |)
            and say STDERR "  FAIL: $d: $p->{canon}: make";
        $this_result->{$p->{canon}}{make} = $rv ? 0 : 1; undef $rv;
        unless ($this_result->{$p->{canon}}{make}) {
            undef $this_result->{$p->{canon}}{test};
            next THIS_PERL;
        }

        $rv = system(qq| make test >> $debugfile 2>&1 |)
            and say STDERR "  FAIL: $d: $p->{canon}: make test";
        $this_result->{$p->{canon}}{test} = $rv ? 0 : 1; undef $rv;

        system(qq| make clean 2>&1 1>/dev/null |)
            and carp "Unable to 'make clean' for $d";
    }
    chdir $self->{temp_top_dir}
        or croak "Unable to change to tempdir $self->{temp_top_dir}";
    return $this_result;
}

=head2 C<print_distro_summary()>

=over 4

=item * Purpose

Create a file holding a summary of the results for running one distro against
each of the selected F<perl>s.

=item * Arguments

        $self->print_distro_summary('Some-Distro');

String holding name of distro.

=item * Return Value

Returns true value on success.

=item * Comment

File created will be named like F</path/to/debugdir/Some-Distro.summary.txt>.

File's content will look like this:

    Attribute-Handlers                                   v5.35.7-48-g34e3587
    {
      "5.006002" => { a => "perl5.6.2",  configure => 1, make => 0, test => undef },
      "5.008009" => { a => "perl5.8.9",  configure => 1, make => 0, test => undef },
      "5.010001" => { a => "perl5.10.1", configure => 1, make => 0, test => undef },
      ...
      "5.034000" => { a => "perl5.34.0", configure => 1, make => 1, test => 1 },
    }

=back

=cut

sub print_distro_summary {
    my ($self, $d) = @_;
    my $output = File::Spec->catfile($self->{debugdir}, "$d.summary.txt");
    open my $OUT, '>', $output or die "Unable to open $output for writing: $!";
    say $OUT sprintf "%-52s%20s" => ($d, $self->{describe});
    my $oldfh = select($OUT);
    dd $self->{results}->{$d};
    close $OUT or die "Unable to close $output after writing: $!";
    select $oldfh;
    say sprintf "%-24s%-48s" => ($d, $output)
        if $self->{verbose};
}

=head1 INTERNAL SUBROUTINES

=head2 C<sanity_check()>

=over 4

=item * Purpose

Assure us that our environment is adequate to the task.

=item * Arguments

    sanity_check(\%distmodules, $verbose);

List of two scalars: (i) reference to the hash which is storing list of
F<dist/> distros; (ii) verbosity selection.

=item * Return Value

Implicitly returns true on success, but does not otherwise return any
meaningful value.

=item * Comment

If verbosity is selected, displays the current git commit and other useful
information on F<STDOUT>.

=back

=cut

sub _sanity_check {
    my ($distmodules, $describe, $verbose) = @_;
    for my $m (keys %{$distmodules}) {
        if ($distmodules->{$m}{UPSTREAM} ne 'blead') {
            warn "Distro $m has UPSTREAM other than 'blead'";
        }
        if ($distmodules->{$m}{MAINTAINER} ne 'P5P') {
            warn "Distro $m has MAINTAINER other than 'P5P'";
        }
    }

    if ($verbose) {
        say "p5-dist-backcompat";
        my $ldescribe = length $describe;
        my $message = q|Found | .
            (scalar keys %{$distmodules}) .
            q| 'dist/' entries in %Maintainers::Modules|;
        my $lmessage = length $message;
        my $ldiff = $lmessage - $ldescribe;
        say sprintf "%-${ldiff}s%s" => ('Results at commit:', $describe);
        say "\n$message";
    }
    return 1;
}

=head2 C<read_manifest()>

=over 4

=item * Purpose

Get a sorted list of all files in F<MANIFEST> (without their descriptions).

=item * Arguments

    read_manifest('/path/to/MANIFEST');

One scalar: the path to F<MANIFEST> in a git checkout of the Perl 5 core distribution.

=item * Return Value

List (sorted) of all files in F<MANIFEST>.

=item * Comments

Depends on C<sort_manifest()> from F<Porting/manifest_lib.pl>.

(This is so elementary and useful that it should probably be in F<Porting/manifest_lib.pl>!)

=back

=cut

sub read_manifest {
    my $manifest = shift;
    open(my $IN, '<', $manifest) or die("Can't read '$manifest': $!");
    my @manifest = <$IN>;
    close($IN) or die($!);
    chomp(@manifest);

    my %seen= ( '' => 1 ); # filter out blank lines
    return grep { !$seen{$_}++ } sort_manifest(@manifest);
}

1;

