package Bio::Das::Request::Feature2Segments;
# $Id$
# this module issues and parses the features command with the feature_id argument

use strict;
use Bio::Das::Type;
use Bio::Das::Segment;
use Bio::Das::Request;
use Bio::Das::Util 'rearrange';

use vars '@ISA';
@ISA = 'Bio::Das::Request';

sub new {
  my $pack = shift;
  my ($dsn,$class,$features,$das,$callback) = rearrange([['dsn','dsns'],
							 'class',
							 ['feature','features'],
							 'das',
							 'callback',
							],@_);
  my $qualified_features;
  if ($class && $das) {
    my $typehandler = Bio::Das::TypeHandler->new;
    my $types = $typehandler->parse_types($class);
    for my $a ($das->aggregators) {
      $a->disaggregate($types,$typehandler);
    }
    my $names = ref($features) ? $features : [$features];
    for my $t (@$types) {
      for my $f (@$names) {
	push @$qualified_features,"$t->[0]:$f";
      }
    }
  } else {
    $qualified_features = $features;
  }

  my $self = $pack->SUPER::new(-dsn => $dsn,
			       -callback  => $callback,
			       -args => { feature_id   => $qualified_features } );
  $self->das($das) if defined $das;
  $self;
}

sub command { 'features' }
sub das {
  my $self = shift;
  my $d    = $self->{das};
  $self->{das} = shift if @_;
  $d;
}

sub t_DASGFF {
  my $self = shift;
  my $attrs = shift;
  if ($attrs) {
    $self->clear_results;
  }
  delete $self->{tmp};
}

sub t_GFF {
  # nothing to do here
}

sub t_SEGMENT {
  my $self = shift;
  my $attrs = shift;
  if ($attrs) {    # segment section is starting
    $self->{tmp}{current_segment} = Bio::Das::Segment->new($attrs->{id},$attrs->{start},
							   $attrs->{stop},$attrs->{version},
							   $self->das,$self->dsn
							  );
  } else {
    $self->add_object($self->{tmp}{current_segment});
  }

}


1;
