package Bio::Das::Request::Types;
# $Id: Types.pm,v 1.2 2002/08/31 23:32:53 lstein Exp $
# this module issues and parses the types command, with arguments -dsn, -segment, -categories, -enumerate

use strict;
use Bio::Das::Type;
use Bio::Das::Segment;
use Bio::Das::Request;
use Bio::Das::Util 'rearrange';

use vars '@ISA';
@ISA = 'Bio::Das::Request';

sub new {
  my $pack = shift;
  my ($dsn,$segments,$categories,$enumerate,$callback) = rearrange([['dsn','dsns'],
								    ['segment','segments'],
								    ['category','categories'],
								    'enumerate',
								    'callback',
								   ],@_);
  my $self = $pack->SUPER::new(-dsn => $dsn,
			       -callback  => $callback,
			       -args => { segment   => $segments,
					  category  => $categories,
					  enumerate => $enumerate,
					} );
  $self;
}

sub command { 'types' }

sub t_DASTYPES {
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
    $self->{tmp}{current_segment} = Bio::Das::Segment->new($attrs->{id},$attrs->{start},$attrs->{stop},$attrs->{version});
    $self->{tmp}{current_type}    = undef;
    $self->{tmp}{types}           = [];
  }

  else {  # reached the end of the segment, so push result
    $self->add_object($self->{tmp}{current_segment},$self->{tmp}{types});
  }

}

sub t_TYPE {
  my $self = shift;
  my $attrs = shift;

  if ($attrs) {  # start of tag
    my $type = $self->{tmp}{current_type} = Bio::Das::Type->new($attrs->{id},$attrs->{method},$attrs->{category});
    $type->source($attrs->{source}) if exists $attrs->{source};
  }

  else {
    my $count = $self->char_data;
    my $type = $self->{tmp}{current_type} or return;
    $type->count($count) if defined $count;
    push (@{$self->{tmp}{types}},$type);
  }
}

# override for "better" behavior
sub results {
  my $self = shift;
  my %r = $self->SUPER::results or return;

  # in array context, return the list of types
  return map { @{$_} } values %r if wantarray;

  # otherwise return ref to a hash
  return \%r;
}


1;
