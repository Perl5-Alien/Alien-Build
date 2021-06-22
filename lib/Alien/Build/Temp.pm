package Alien::Build::Temp;

use strict;
use warnings;
use 5.008004;
use Carp ();
use Path::Tiny ();
use File::Temp ();
use File::Spec ();

# ABSTRACT: Temp Dir support for Alien::Build
# VERSION

=head1 DESCRIPTION

This class is private to L<Alien::Build>.

=cut

# problem with vanilla File::Temp is that is often uses
# as /tmp that has noexec turned on.  Workaround is to
# create a temp directory in the build directory, but
# we have to be careful about cleanup.  This puts all that
# (attempted) carefulness in one place so that when we
# later discover it isn't so careful we can fix it in
# one place rather than all the places that we need
# temp directories.

my %root;

sub _root
{
  return File::Spec->tmpdir if $^O eq 'MSWin32';

  my $root = Path::Tiny->new(-d "_alien" ? "_alien/tmp" : ".tmp")->absolute;
  unless(-d $root)
  {
    mkdir $root or die "unable to create temp root $!";
  }

  # TODO: doesn't account for fork...
  my $lock = $root->child("l$$");
  unless(-f $lock)
  {
    open my $fh, '>', $lock;
    close $fh;
  }
  $root{"$root"} = 1;
  $root;
}

END {
  foreach my $root (keys %root)
  {
    my $lock = Path::Tiny->new($root)->child("l$$");
    unlink $lock;
    # try to delete if possible.
    # if not possible then punt
    rmdir $root if -d $root;
  }
}

sub newdir
{
  my $class = shift;
  Carp::croak "uneven" if @_ % 2;
  File::Temp->newdir(DIR => _root, @_);
}

sub new
{
  my $class = shift;
  Carp::croak "uneven" if @_ % 2;
  File::Temp->new(DIR => _root, @_);
}

1;
