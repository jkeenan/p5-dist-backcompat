#!/usr/bin/env perl
use 5.14.0;
use warnings;
use Cwd qw( cwd );
use Data::Dumper;$Data::Dumper::Indent=1;
use File::Copy qw( copy );
use File::Find qw( find );
use File::Spec;
use File::Temp qw( tempdir );
use Getopt::Long qw( GetOptions );
# From CPAN
use File::Copy::Recursive::Reduced qw( dircopy );
use Data::Dump qw( dd pp );

# TODO: Check that we're in the top-level directory of the core distribution,
# preferably in a way consistent with other Porting/ programs.

=head1 NAME

Porting/dist-backcompat.pl - Will changes to F<dist/> build on older C<perl>s?

=head1 SYNOPSIS

    $ perl Porting/dist-backcompat.pl --verbose \
        --distro Search-Dict \
        --distro Safe \
        --distro=Data-Dumper 2>&1 | tee /tmp/dist-backcompat.out

=head1 PREREQUISITES

F<perl> 5.14.0 or newer, with the following modules installed from CPAN:

=over 4

=item * F<Data::Dump>

=item * F<File::Copy::Recursive::Reduced>

=back

=head1 COMMAND-LINE SWITCHES

=over 4

=item * C<--verbose>

Flag.  Extra helpful output on F<STDOUT>.

=item * C<--distro>

Switch-parameter pair.  Parameter should be hyphen-separated name of directory
under F</dist>, I<e.g.>, C<ExtUtils-ParseXS>, not C<ExtUtils::ParseXS>.  May
be called more than once, I<e.g.>:

    --distro Search-Dict --distro Safe --distro=Data-Dumper

=item * C<--host>

Switch-parameter pair.  Parameter should be the string returned by the system
F<hostname> call.  Defaults to C<dromedary.p5h.org>.

=item * C<--path_to_perls>

Switch-parameter pair.  Parameter should be an absolute path to the directory
holding binary executables of older F<perl>s.  Defaults to
F</media/Tux/perls-t/bin>.

=back

=head1 DESCRIPTION

As of Jan 09 2022, there are 41 distributions ("distros") underneath F<dist/>
in the Perl 5 core distribution.  By definition, all of these are maintained
by Perl 5 Porters in core but are potentially releasable to CPAN so that they
may be installed against older F<perl>s.  (As of that date, all but one of
those 41 distros has had at least one CPAN release in the past.)

But if were to release the code in a given F<dist/> distro to CPAN today,
would it build and test correctly against older F<perl>s?  I<Which> older
F<perl>s?  More to the point, suppose that we've made changes to the code in
these distros in core since the last production release of F<perl>?  If we
were to release I<that> code to CPAN, would that code fail against older
versions of F<perl>?

This program, F<Porting/dist-backcompat.pl>, aims to be a P5P core development
tool which, when run in advance of a development, production or maintenance
release of F<perl>, can alert a release manager or core developer to potential
problems as described above.

=head2 Terminology

Every one of the F<dist/> distros has its own history, quirks and coding
challenges.  So within this program we will use certain terminology to group
distros that share certain characteristics.

=head3 CPAN Viability

Setting aside metadata files like F<META.json>, F<META.yml> and F<Changes>, if
we were to take the code for a given F<dist/> distro as it stands today, added
a F<Makefile.PL> as needed (see next section), rolled it up into a tarball and
uploaded that tarball to CPAN, how would that CPAN release fare on
L<CPANtesters|https://www.cpantesters.org> against older versions of F<perl>?

If such a release required a lot of fine-tuning in order to get C<PASS>es on
CPANtesters, then we would say it has I<low> direct CPAN viability.

If such a release required little fine-tuning to get those C<PASS>es, then we
would say it has I<high> direct CPAN viability.

=head3 F<Makefile.PL> Status

When any of these F<dist/> distros gets a CPAN release, it needs to have a
F<Makefile.PL> so that F<ExtUtils::MakeMaker> can generated a F<Makefile>.
But that doesn't mean that a given F<dist/> distro has a F<Makefile.PL> of its
own within the core distribution.  We can classify these distros according to
the following statuses:

=over 4

=item * C<unreleased>

This kind of F<dist/> distro has apparently never had a CPAN release, so it
has never needed a F<Makefile.PL> for that purpose and doesn't have one in
core.

=item * C<native>

This kind of F<dist/> distro has its own F<Makefile.PL> directly coded in its
directory underneath F<dist/> in core.  Such a distro may -- I<or may not> --
use that very same F<Makefile.PL> in its CPAN release.

=item * C<generated>

This kind of F<dist/> distro does not have its own F<Makefile.PL> directly
coded in its directory underneath F<dist/> in core.  Instead, its
F<Makefile.PL> is generated during the Perl 5 build process (I<e.g.,> by a
program called within F<make> such as F<make_ext.pl>).  Such a distro may --
I<or may not> -- use that F<Makefile.PL> in its CPAN release.

=item * C<cpan>

This kind of F<dist/> distro has no F<Makefile.PL> of its own in the core
distribution -- neither C<native> nor C<generated>.  Hence, when released to
CPAN, the CPAN maintainer has to provide an appropriate, directly coded
F<Makefile.PL> as part of the tarball.

=back

As of the date of this progam, the 4 different Makefile.PL statuses have these
counts:

    unreleased           1
    native              15
    generated            4
    cpan                21

As a consequence of this variation, this program will have to jump through
significant hoops to get a reasonable estimate of the CPAN viability of each
F<dist/> distro.

=cut

##### CHECK ENVIRONMENT #####

my ($verbose, $host, $path_to_perls) = ('') x 3;
my @distros_requested = ();
GetOptions(
    "verbose"           => \$verbose,
    "distro=s"          => \@distros_requested,
    "host=s"            => \$host,
    "path_to_perls=s"   => \$path_to_perls,
) or die "Unable to get command-line options: $!";

my @wanthyphens = ();
for my $d (@distros_requested) {
    if ($d =~ m/::/) {
        push @wanthyphens, $d;
    }
}
if (@wanthyphens) {
    warn "$_: supply distribution name in 'Some-Distro' format, not 'Some::Distro'"
        for @wanthyphens;
    die "'distro' switch in incorrect format: $!";
}

my $describe = `git describe`;
chomp($describe);

my $dir = cwd();
my $maint_file = File::Spec->catfile($dir, 'Porting', 'Maintainers.pl');
require $maint_file;   # to get %Modules in package Maintainers

my $manilib_file = File::Spec->catfile($dir, 'Porting', 'manifest_lib.pl');
require $manilib_file; # to get function sort_manifest()

my %distmodules = ();
for my $m (keys %Maintainers::Modules) {
    if ($Maintainers::Modules{$m}{FILES} =~ m{dist/}) {
        $distmodules{$m} = $Maintainers::Modules{$m};
    }
}

# Sanity checks; all modules under dist/ should be blead-upstream and have P5P
# as maintainer.
sanity_check(\%distmodules, $verbose);


my $metadata_file = File::Spec->catfile($dir, 'Porting', 'dist-backcompat-distro-metadata.txt');
my %distro_metadata = ();

open my $IN, '<', $metadata_file or die "Unable to open $metadata_file for reading: $!";
while (my $l = <$IN>) {
    chomp $l;
    next if $l =~ m{^(\#|\s*$)};
    my @rowdata = split /\|/, $l;
    # Refine this later
    #$distro_metadata{$rowdata[0]} = { minimum_perl_version => $rowdata[1] || '' };
    $distro_metadata{$rowdata[0]} = {
        minimum_perl_version => $rowdata[1] // '',
        needs_threads        => $rowdata[2] // '',
    };
}
close $IN or die "Unable to close $metadata_file after reading: $!";
#dd \%distro_metadata;
#exit 0;

##### ANALYZE dist/ DISTROS #####

# Order of Battle:

# First, identify any dist/ distros which appear not to have current releases
# on CPAN.  We'll call these 'unreleased'.

my %makefile_pl_status = ();

for my $m (keys %distmodules) {
    if (! exists $distmodules{$m}{DISTRIBUTION}) {
        my ($distname) = $distmodules{$m}{FILES} =~ m{^dist/(.*)/?$};
        $makefile_pl_status{$distname} = 'unreleased';
    }
}

# Second, identify those dist/ distros which have their own hard-coded
# Makefile.PLs in the core distribution.  We'll call these 'native'.

my $manifest = File::Spec->catfile($dir, 'MANIFEST');
my @sorted = read_manifest($manifest);

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

find(\&get_generated_makefiles, ( "$dir/dist" ));

# Fourth, identify those dist/ distros whose Makefile.PLs must presumably be
# obtained from CPAN.

for my $d (sort keys %distmodules) {
    next unless exists $distmodules{$d}{FILES};
    # pattern below can be simplified once
    # https://github.com/Perl/perl5/pull/19336 is accepted
    my ($distname) = $distmodules{$d}{FILES} =~ m{^dist/(.*)/?$};
    if (! exists $makefile_pl_status{$distname}) {
        $makefile_pl_status{$distname} = 'cpan';
    }
}

show_makefile_pl_status(\%makefile_pl_status, $verbose);

my @distros_for_testing = (scalar @distros_requested)
    ? @distros_requested
    : sort grep { $makefile_pl_status{$_} ne 'unreleased' } keys %makefile_pl_status;
if ($verbose) {
    say "\nWill test ", scalar @distros_for_testing,
        " distros which have been presumably released to CPAN:";
    say "  $_" for @distros_for_testing;
}

##### ASSEMBLE OLDER PERL EXECUTABLES #####

# The balance of this will have to be tested on Dromedary in order to
# have access to the older perl executables compile by Tux.
#
# SANITY CHECKING:  Once on Dromedary, demonstrate that we can locate Tux's
# executables.
#
# OUTER_LOOP: Loop over all the modules listed by keys in %makefile_pl_status,
# or in only those modules requested on command-line and stored in
# %distros_requested.  Construct a CPAN-style distribution for each, getting
# an appropriate Makefile.PL as needed from source, built source or CPAN, and
# adding files in the EXCLUDED list by getting them from CPAN.
#
# INNER_LOOP: Loop over the list of older perl executables.  Call 'thisperl
# Makefile.PL; make; make test' on the current distro, noting failures at any
# stage.

my $this_host = $ENV{HOSTNAME} // `hostname`;
chomp $this_host;
$host ||= 'dromedary.p5h.org';
if ($this_host ne $host) {
    say "\nNot on $host; exiting" if $verbose;
    exit(0);
}

say '' if $verbose;
$path_to_perls ||= '/media/Tux/perls-t/bin';

my $older_perls = File::Spec->catfile('Porting', 'dist-backcompat-older-perls.txt');
my @perllist = ();
open my $IN1, '<', $older_perls or die "Unable to open $older_perls for reading: $!";
while (my $l = <$IN1>) {
    chomp $l;
    next if $l =~ m{^(\#|\s*$)};
    push @perllist, $l;
}
close $IN1 or die "Unable to close $older_perls after reading: $!";

my $perls = validate_older_perls(\@perllist, $path_to_perls, $verbose);
#pp($perls); exit 0;

my $tdir = tempdir( CLEANUP => 1 );
my $debugdir = tempdir();
my $currdir = cwd();
my $results;

for my $d (@distros_for_testing) {
    say ''; # for more readable output
    $results = test_one_distro_against_older_perls( {
        d               => $d,
        dir             => $dir,
        tdir            => $tdir,
        currdir         => $currdir,
        debugdir        => $debugdir,
        perls           => $perls,
        results         => $results,
        verbose         => $verbose,
    } );
}

#dd $results;
if ($verbose) {
    say "\nSummaries";
    say '-' x 9;
}

for my $d (sort keys %{$results}) {
    print_distro_summary($results, $debugdir, $d, $describe, $verbose);
}

say "\nFinished!" if $verbose;

##### SUBROUTINES #####

=head1 SUBROUTINES

None of the subroutines described below are intended to be exportable from
this program.  They are documented only for the convenience of Perl 5 Porters
and others working on the Perl 5 core distribution.

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

sub sanity_check {
    my ($distmodules, $verbose) = @_;
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

=head2 C<get_generated_makefiles()>

=over 4

=item * Purpose

Identify those distros under F<dist/> whose F<Makefile.PL>s are generated by
the Perl 5 build process.

=item * Arguments

None, as this is a C<\&wanted>-style code reference for C<File::Find::find>.

=item * Return Value

None.

=item * Comment

Internally assigns to the hash holding the status of F<Makefile.PL>s.

=back

=cut

sub get_generated_makefiles {
    if ( $File::Find::name =~ m{^$dir/dist/(.*?)/Makefile\.PL$} ) {
        my $distro = $1;
        if (! exists $makefile_pl_status{$distro}) {
            $makefile_pl_status{$distro} = 'generated';
        }
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

=head2 C<show_makefile_pl_status>

=over 4

=item * Purpose

Display a chart listing F<dist/> distros in one column and the status of their respective F<Makefile.PL>s in the second column.

=item * Arguments

    show_makefile_pl_status(\%makefile_pl_status, $verbose);

List of two scalars:  (i) Reference to the hash holding status of F<Makefile.PL> for each F<dist/> distro; (ii) verbosity request.

=item * Return Value

Implicitly returns true on success, but does not otherwise return any meaningful value.

=back

=cut

sub show_makefile_pl_status {
    my ($status, $verbose) = @_;
    my %counts;
    for my $module (sort keys %{$status}) {
        $counts{$status->{$module}}++;
    }
    if ($verbose) {
        for my $k (sort keys %counts) {
            printf "  %-18s%4s\n" => ($k, $counts{$k});
        }
        say '';
        printf "%-24s%-12s\n" => ('Distribution', 'Status');
        printf "%-24s%-12s\n" => ('------------', '------');
        for my $module (sort keys %{$status}) {
            printf "%-24s%-12s\n" => ($module, $status->{$module});
        }
    }
}

=head2 C<validate_older_perls()>

=over 4

=item * Purpose

Validate the paths and executability of the older perl versions against which we're going to test F<dist/> distros.

=item * Arguments

    my @perls = validate_older_perls(
        \@perllist, $path_to_perls, $verbose);

List of 3 scalars: (i) reference to the list of older perls; (ii) absolute path to the directory holding those older executables; (iii) verbosity selection.

=item * Return Value

Array ref holding one hash reference for each older version of perl to be used.

=back

=cut

sub validate_older_perls {
    my ($perllistref, $path_to_perls, $verbose) = @_;
    my @perls = ();

    for my $p (@{$perllistref}) {
        say "Locating $p executable ..." if $verbose;
        my $rv;
        my $path_to_perl = File::Spec->catfile($path_to_perls, $p);
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
    return [ @perls ];
}

=head2 C<test_one_distro_against_older_perls()>

=over 4

=item * Purpose

Use each of designated older F<perl> executables to configure, build and test
one F<dist/> distribution.

=item * Arguments

    $results = test_one_distro_against_older_perls( {
        d               => $d,
        dir             => $dir,
        tdir            => $tdir,
        currdir         => $currdir,
        debugdir        => $debugdir,
        perls           => $perls,
        results         => $results,
        verbose         => $verbose,
    } );

Single hash reference with 8 key-value pairs.  The C<$results> hashref is one
of those KVPs, is returned by the subroutine and is then fed back into the
next iteration of the subroutine.

=item * Return Value

Hash reference augmented by results from one distro on each iteration.

=back

=cut

sub test_one_distro_against_older_perls {
    my $args = shift;
    say "Testing $args->{d} ..." if $args->{verbose};
    my $source_dir = File::Spec->catdir($args->{dir}, 'dist', $args->{d});
    my $this_tempdir  = File::Spec->catdir($args->{tdir}, $args->{d});
    mkdir $this_tempdir or die "Unable to mkdir $this_tempdir";
    my $testpl = File::Spec->catfile($args->{dir}, 't', 'test.pl');
    die "Could not locate $testpl" unless -f $testpl;
    my $this_tdir = File::Spec->catdir($this_tempdir, 't');
    mkdir $this_tdir or die "Unable to mkdir $this_tdir";
    copy $testpl => $this_tdir or die "Unable to copy $testpl";
    dircopy($source_dir, $this_tempdir)
        or die "Unable to copy $source_dir to $this_tempdir: $!";
    chdir $this_tempdir or die "Unable to chdir to tempdir: $!";
    THIS_PERL: for my $p (@{$args->{perls}}) {
        $args->{results}->{$args->{d}}{$p->{canon}}{a} = $p->{version};
        # Skip this perl version if (a) distro has a specified
        # 'minimum_perl_version' and (b) that minimum version is greater than
        # the current perl we're running.
        if (
            (
                $distro_metadata{$args->{d}}{minimum_perl_version}
                    and
                $distro_metadata{$args->{d}}{minimum_perl_version} >= $p->{canon}
            )
#                or
#            (
#                $distro_metadata{$args->{d}}{needs_threads}
#            )
        ) {
            $args->{results}->{$args->{d}}{$p->{canon}}{configure} = undef;
            $args->{results}->{$args->{d}}{$p->{canon}}{make} = undef;
            $args->{results}->{$args->{d}}{$p->{canon}}{test} = undef;
            next THIS_PERL;
        }
        my $f = join '.' => ($args->{d}, $p->{version}, 'txt');
        my $debugfile = File::Spec->catfile($args->{debugdir}, $f);
        if ($args->{verbose}) {
            say "Testing $args->{d} with $p->{canon} ($p->{version}); see $debugfile";
        }
        my $rv;
        $rv = system(qq| $p->{path} Makefile.PL > $debugfile 2>&1 |)
            and say STDERR "  FAIL: $args->{d}: $p->{canon}: Makefile.PL";
        $args->{results}->{$args->{d}}{$p->{canon}}{configure} = $rv ? 0 : 1; undef $rv;
        unless ($args->{results}->{$args->{d}}{$p->{canon}}{configure}) {
            undef $args->{results}->{$args->{d}}{$p->{canon}}{make};
            undef $args->{results}->{$args->{d}}{$p->{canon}}{test};
            next THIS_PERL;
        }

        $rv = system(qq| make >> $debugfile 2>&1 |)
            and say STDERR "  FAIL: $args->{d}: $p->{canon}: make";
        $args->{results}->{$args->{d}}{$p->{canon}}{make} = $rv ? 0 : 1; undef $rv;
        unless ($args->{results}->{$args->{d}}{$p->{canon}}{make}) {
            undef $args->{results}->{$args->{d}}{$p->{canon}}{test};
            next THIS_PERL;
        }

        $rv = system(qq| make test >> $debugfile 2>&1 |)
            and say STDERR "  FAIL: $args->{d}: $p->{canon}: make test";
        $args->{results}->{$args->{d}}{$p->{canon}}{test} = $rv ? 0 : 1; undef $rv;
    }
    chdir $args->{currdir} or die "Unable to chdir back after testing: $!";
    return $args->{results};
}

=head2 C<print_distro_summary()>

=over 4

=item * Purpose

Print a summary of the results for one distro for all designated F<perl>
executables to a file in the debugging directory.

=item * Arguments

    print_distro_summary(
        $results, $debugdir, $d, $describe, $verbose
    );

List of 5 scalars: hash reference holding results; absolute path to the
debugging director; name of distribution; current output of F<git describe>;
verbosity selection.

=item * Return Value

Implicitly returns true upon success.

=back

=cut

sub print_distro_summary {
    my ($results, $debugdir, $d, $describe, $verbose) = @_;
    my $output = File::Spec->catfile($debugdir, "$d.summary.txt");
    open my $OUT, '>', $output or die "Unable to open $output for writing: $!";
    say $OUT sprintf "%-52s%20s" => ($d, $describe);
    my $oldfh = select($OUT);
    dd $results->{$d};
    close $OUT or die "Unable to close $output after writing: $!";
    select $oldfh;
    say sprintf "%-24s%-48s" => ($d, $output)
        if $verbose;
}
