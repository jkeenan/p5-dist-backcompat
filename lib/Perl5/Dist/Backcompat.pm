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
    my %valid_params = map {$_ => 1} qw( verbose host path_to_perls );
    my @invalid_params = ();
    for my $p (keys %$params) {
        push @invalid_params, $p unless $valid_params{$p};
    }
    if (@invalid_params) {
        my $msg = "Constructor parameter(s) @invalid_params not valid";
        croak $msg;
    }

    my $data = {};
    for my $p (keys %valid_params) {
        $data->{$p} = (defined $params->{$p}) ? $params->{$p} : '';
    }
    #pp($data);
    $data->{host} ||= 'dromedary.p5h.org';
    $data->{path_to_perls} ||= '/media/Tux/perls-t/bin';

    return bless $data, $class;
}


1;
# The preceding line will help the module return a true value

