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

=head1 METHODS

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

# Variables I'll need to build the object (* means: currently supplied via
# command-line)
#
# perl_workdir: absolute path to git checkout of Perl 5 core distribution
# ## confirm MANIFEST
# ## confirm Porting/Maintainers.pl
# ## confirm Porting/manifest_lib.pl
# describe:     r.v. for 'git describe' in perl_workdir
# verbose *
# %distmodules: processed from Porting/Maintainers.pl
# %distro_metadata: processed from etc/dist-backcompat-distro-metadata.txt
# %makefile_pl_status (or is this what the constructor builds?): processed in
# part from MANIFEST
# @distros_for_testing * : not in constructor, make argument of subsequent
# method
# host *
# path_to_perls *
# paths to output files, tempfiles, etc.: not in constructor, make argument of subsequent method
#
# Currently existing subroutines:
# sanity_check
# get_generated_makefiles
# read_manifest
# show_makefile_pl_status
# validate_older_perls
# test_one_distro_against_older_perls
# print_distro_summary
## Which of the above need to be methods; which are auxiliary?


sub new {
    my ($class, $params) = @_;
    if (defined $params and ref($params) ne 'HASH') {
        croak "Argument supplied to constructor must be hashref";
    }
    my %valid_params = map {$_ => 1} qw( verbose host path_to_perls perl_workdir );
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

    return bless $data, $class;
}

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
        $self->{perl_workdir}, 'Porting', 'dist-backcompat-distro-metadata.txt');
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
        };
    }
    close $IN or die "Unable to close $metadata_file after reading: $!";
    $self->{distro_metadata} = \%distro_metadata;

    return $self;
}

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

    sub get_generated_makefiles {
        my $self = shift;
        my $pattern = qr{/dist/(.*?)/Makefile\.PL$};
        if ( $File::Find::name =~ m{$pattern} ) {
            my $distro = $1;
            if (! exists $self->{makefile_pl_status}->{$distro}) {
                $self->{makefile_pl_status}->{$distro} = 'generated';
            }
        }
    }
    find(
        \&get_generated_makefiles,
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
    $self->{makefile_pl_status} = \%makefile_pl_status;
    return $self;
}

=head1 METHODS

TK

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
        say "Porting/dist-backcompat.pl";
        my $ldescribe = length $describe;
        my $message = q|Found | .
            (scalar keys %{$distmodules}) .
            q| 'dist/' entries in %Maintainers::Modules|;
        my $lmessage = length $message;
        my $ldiff = $lmessage - $ldescribe;
        say sprintf "%-${ldiff}s%s" => ('Results at commit:', $describe);
        say "\n$message";
    }
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

