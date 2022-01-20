# -*- perl -*-
# t/003-verbose.t
use strict;
use warnings;

use Test::More;
unless ($ENV{PERL_AUTHOR_TESTING}) {
    plan skip_all => "author testing only";
}
else {
    #plan tests => 63;
    plan tests => 34;
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

    for my $d ( 'Data-Dumper', 'PathTools', 'Storable', 'Time-HiRes',
        'threads', 'threads-shared' ) {
        ok($self->{distro_metadata}->{$d}->{needs_ppport_h},
            "$d has 'needs_ppport_h' set");
    }
    my $e = 'threads';
    ok($self->{distro_metadata}->{$e}->{needs_threads_h},
        "$e has 'needs_threads_h' set");
    $e = 'threads-shared';
    ok($self->{distro_metadata}->{$e}->{needs_shared_h},
        "$e has 'needs_shared_h' set");
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

my @distros_requested = (
    'base',
    'threads',
    'threads-shared',
    'Data-Dumper',
);
my $count_exp = scalar(@distros_requested);
my @distros_for_testing = $self->get_distros_for_testing(\@distros_requested);
is(@distros_for_testing, $count_exp,
    "Will test $count_exp distros, as expected");

my @perls = $self->validate_older_perls();
my $expected_perls = 15;
cmp_ok(@perls, '>=', $expected_perls,
    "Validated at least $expected_perls older perl executables (5.6 -> 5.34)");

note("Beginning processing of requested distros;\n  this will take some time ...");
my $debugdir = tempdir();
my $rv = $self->test_distros_against_older_perls($debugdir);
ok($rv, "test_distros_against_older_perls() returned true value");
ok(-d $self->{debugdir}, "debugging directory $self->{debugdir} located");
for my $d (@{$self->{distros_for_testing}}) {
    ok($self->{results}->{$d}, "Got a result for '$d'");
#    pp( { %{$self->{results}->{$d}} } );
}

$rv = $self->print_distro_summaries();
ok($rv, "print_distro_summaries() returned true value");

$rv = $self->print_distro_summaries( {cat_summaries => 1} );
ok($rv, "print_distro_summaries() with cat_summaries set returned true value");

my $results_ref = $self->tally_results();
is(ref($results_ref), 'ARRAY', "tally_results() returned array ref");
is(scalar @{$results_ref}, 4, "Got 4 items in results: @{$results_ref}");

__END__
