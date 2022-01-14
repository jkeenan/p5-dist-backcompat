# -*- perl -*-
# t/003-verbose.t
use strict;
use warnings;

use Test::More;
unless ($ENV{PERL_AUTHOR_TESTING}) {
    plan skip_all => "author testing only";
}
else {
    plan tests => 45;
}
use Capture::Tiny qw( capture_stdout capture );
use Data::Dump qw( dd pp );
use File::Temp qw( tempdir );

use_ok( 'Perl5::Dist::Backcompat' );

note("Object to be created with request for verbosity");

my $self = Perl5::Dist::Backcompat->new( {
    perl_workdir => $ENV{PERL_WORKDIR},
    verbose => 1,
} );
ok(-d $self->{perl_workdir}, "Located git checkout of perl");

{
    my $rv;
    my $stdout = capture_stdout { $rv = $self->init(); };
    ok($rv, "init() returned true value");
    ok($stdout, "verbosity requested; STDOUT captured");
    like($stdout, qr/p5-dist-backcompat/s, "STDOUT captured from init()");
    like($stdout, qr/Results at commit/s, "STDOUT captured from init()");
    like($stdout, qr/Found\s\d+\s'dist\/'\sentries/s, "STDOUT captured from init()");

}

my @parts = ( qw| Search Dict | );
my $sample_module = join('::' => @parts);
my $sample_distro = join('-' => @parts);
note("Using $sample_distro as an example of a distro under dist/");

ok($self->{distmodules}{$sample_module}, "Located data for module $sample_module");
ok($self->{distro_metadata}{$sample_distro}, "Located metadata for module $sample_distro");

ok($self->categorize_distros(), "categorize_distros() returned true value");
ok($self->{makefile_pl_status}{$sample_distro},
    "Located Makefile.PL status for module $sample_distro");

{
    my $rv;
    my $stdout = capture_stdout { $rv = $self->show_makefile_pl_status(); };
    ok($rv, "show_makefile_pl_status() completed successfully");
    ok($stdout, "verbosity requested; STDOUT captured");
    like($stdout, qr/Distribution\s+Status/s,
        "got expected chart header from show_makefile_pl_status");
}

{
    my @distros_requested = (
        'base',
        'threads',
        'threads-shared',
        'Data-Dumper',
    );
    my $count_exp = scalar(@distros_requested);
    my @distros_for_testing;
    my $stdout = capture_stdout {
        @distros_for_testing = $self->get_distros_for_testing(\@distros_requested);
    };
    is(@distros_for_testing, $count_exp,
        "Will test $count_exp distros, as expected");
    ok($stdout, "verbosity requested; STDOUT captured");
    like($stdout, qr/Will test $count_exp distros/s,
        "STDOUT captured from get_distros_for_testing()");
    for my $d (@distros_requested) {
        like($stdout, qr/$d/s, "STDOUT captured from get_distros_for_testing()");
    }
}

{
    my @perls;
    my $stdout = capture_stdout { @perls = $self->validate_older_perls(); };
    my $expected_perls = 15;
    cmp_ok(@perls, '>=', $expected_perls,
        "Validated at least $expected_perls older perl executables (5.6 -> 5.34)");
    ok($stdout, "verbosity requested; STDOUT captured");
    like($stdout, qr/Locating perl5.*?executable\s\.{3}/s,
        "STDOUT captured from validate_older_perls()");
}

note("Beginning processing of requested distros;\n  this will take some time ...");
my $debugdir = tempdir( CLEANUP => 1 );
{
    my ($stdout, $stderr) =
        capture { $self->test_distros_against_older_perls($debugdir); };
    ok(-d $self->{debugdir}, "debugging directory $self->{debugdir} located");
    for my $d (@{$self->{distros_for_testing}}) {
        ok($self->{results}->{$d}, "Got a result for '$d'");
    }
    ok($stdout, "verbosity requested; STDOUT captured");
    # We'll assume that we tested each distro at least once, that being
    # with the most recent perl executable in the list.
    my $latest_perl = $self->{perls}[-1]->{canon};
    for my $d (@{$self->{distros_for_testing}}) {
        ok($self->{results}->{$d}, "Got a result for '$d'");
        like($stdout, qr/Testing $d with $latest_perl/s,
            "Got verbose output for $d tested against $latest_perl");
    }
    if (length $stderr) {
        my $note = "Some distros FAILed against some perls ...\n";
        $note .= $stderr;
        note($note);
    }
    ($stdout, $stderr) = (undef) x 2;

    my $rv;
    $stdout = capture_stdout { $rv = $self->print_distro_summaries(); };
    ok($rv, "print_distro_summaries() returned true value");
    ok($stdout, "verbosity requested; STDOUT captured");
    like($stdout, qr/Summaries/s, "STDOUT captured from print_distro_summaries()");
    for my $d (@{$self->{distros_for_testing}}) {
        like($stdout, qr/$d.*?$d\.summary\.txt/s, "STDOUT captured from print_distro_summaries()");
    }
}

