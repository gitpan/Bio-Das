package Bio::Das::FeatureIterator;

use strict;
require Exporter;
use Carp 'croak';
use vars qw($VERSION);

$VERSION = '0.01';

sub new {
  my $class = shift;
  $class = ref($class) if ref($class);

  my $features = shift;
  return bless $features,$class;
}

sub next_seq {
  my $self = shift;
  return unless @$self;
  return shift @$self;
}

1;
