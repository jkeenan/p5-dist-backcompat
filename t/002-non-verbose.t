# -*- perl -*-
# t/002-non-verbose.t
use strict;
use warnings;

use Test::More;
unless ($ENV{PERL_AUTHOR_TESTING}) {
    plan skip_all => "author testing only";
}
else {
    plan tests => 14;
}
use Capture::Tiny qw( capture_stdout );
use Data::Dump qw( dd pp );

use_ok( 'Perl5::Dist::Backcompat' );

note("Object to be created with no request for verbosity");
my $self = Perl5::Dist::Backcompat->new( {
    perl_workdir => $ENV{PERL_WORKDIR},
    verbose => 0,
} );
ok(-d $self->{perl_workdir}, "Located git checkout of perl");

{
    my $rv;
    my $stdout = capture_stdout { $rv = $self->init(); };
    ok($rv, "init() returned true value");
    ok(! $stdout, "verbosity not requested; hence no STDOUT captured");
}

my @parts = ( qw| Search Dict | );
my $sample_module = join('::' => @parts);
my $sample_distro = join('-' => @parts);
note("Using $sample_distro as an example of a distro under dist/");

ok($self->{distmodules}{$sample_module}, "Located data for module $sample_module");
ok($self->{distro_metadata}{$sample_distro}, "Located metadata for module $sample_distro");
my $tb = $self->{distro_metadata}{$sample_distro}{tarball};
ok(-f $tb, "Located tarball $tb for module $sample_distro");

ok($self->categorize_distros(), "categorize_distros() returned true value");
ok($self->{makefile_pl_status}{$sample_distro},
    "Located Makefile.PL status for module $sample_distro");
#pp( { %{$self->{makefile_pl_status}} } );
my %categories_seen = ();
for my $category (values %{$self->{makefile_pl_status}}) {
    $categories_seen{$category}++;
}

{
    my $rv;
    my $stdout = capture_stdout { $rv = $self->show_makefile_pl_status(); };
    ok($rv, "show_makefile_pl_status() completed successfully");
    ok(! $stdout, "verbosity not requested; hence no STDOUT captured");
}

{
    local $@;
    my @distros_for_testing = ();
    eval {
        @distros_for_testing =
            $self->get_distros_for_testing( { "Attribute-Handlers" => 1 } );
    };
    like($@, qr/\QArgument passed to get_distros_for_testing() must be arrayref\E/,
        "Wrong type of argument to get_distros_for_testing()");
}

{
    my @distros_for_testing = $self->get_distros_for_testing();
    my @categorized = keys %{$self->{makefile_pl_status}};
    my @expected = grep { $self->{makefile_pl_status}{$_} ne 'unreleased' }
        @categorized;
    is(scalar @distros_for_testing,
       scalar @expected,
       "With no argument to get_distros_for_testing(), " .
            "all released distros are selected for testing"
    );
}

my @perls = $self->validate_older_perls();
my $expected_perls = 15;
cmp_ok(@perls, '>=', $expected_perls,
    "Validated at least $expected_perls older perl executables (5.6 -> 5.34)");
