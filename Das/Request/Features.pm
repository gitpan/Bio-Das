package Bio::Das::Request::Features;
# $Id: Features.pm,v 1.4 2002/10/25 19:20:09 lstein Exp $
# this module issues and parses the types command, with arguments -dsn, -segment, -categories, -enumerate

use strict;
use Bio::Das::Type;
use Bio::Das::Feature;
use Bio::Das::Segment;
use Bio::Das::Request;
use Bio::Das::Util 'rearrange';

use vars '@ISA';
@ISA = 'Bio::Das::Request';

sub new {
  my $pack = shift;
  my ($dsn,$segments,$types,$categories,$feature_id,$group_id,$callback) = rearrange([
										      'dsn',
										      ['segment','segments'],
										      ['type','types'],
										      ['category','categories'],
										      'feature_id',
										      'group_id',
										      'callback'
							       ],@_);
  my $self = $pack->SUPER::new(-dsn => $dsn,
			       -callback => $callback,
			       -args => { segment    => $segments,
					  category   => $categories,
					  type       => $types,
					  feature_id => $feature_id,
					  group_id   => $group_id,
					} );
  $self;
}

sub command { 'features' }

sub t_DASGFF {
  my $self = shift;
  my $attrs = shift;
  if ($attrs) {
    $self->clear_results;
  }
  delete $self->{tmp};
}

sub t_GFF {
  # nothing to do here -- probably should check version
}

sub t_SEGMENT {
  my $self = shift;
  my $attrs = shift;
  if ($attrs) {    # segment section is starting
    $self->{tmp}{current_segment} = Bio::Das::Segment->new($attrs->{id},$attrs->{start},$attrs->{stop},$attrs->{version});
    $self->{tmp}{current_feature} = undef;
    $self->{tmp}{features}        = [];
  }

  else {  # reached the end of the segment, so push result
    $self->add_object($self->{tmp}{current_segment},$self->{tmp}{features}) unless $self->callback;
  }

}

# do nothing
sub t_UNKNOWNSEGMENT { }
sub t_ERRORSEGMENT { }

sub t_FEATURE {
  my $self = shift;
  my $attrs = shift;

  if ($attrs) {  # start of tag
    my $feature = $self->{tmp}{current_feature} = Bio::Das::Feature->new($self->{tmp}{current_segment},
									 $attrs->{id}
									);
    $feature->label($attrs->{label}) if exists $attrs->{label};
    $self->{tmp}{type} = undef;
  }

  else {
    # feature is ending. This would be the place to do group aggregation
    my $feature = $self->{tmp}{current_feature};
    if (my $callback = $self->callback) {
      $callback->($feature);
    } else {
      push @{$self->{tmp}{features}},$feature;
    }
  }
}

sub t_TYPE {
  my $self = shift;
  my $attrs = shift;
  my $feature = $self->{tmp}{current_feature} or return;

  my $cft = $self->{tmp}{type} ||= Bio::Das::Type->new();

  if ($attrs) {  # tag starts
    $cft->id($attrs->{id});
    $cft->category($attrs->{category}) if $attrs->{category};
  } else {

    # possibly add a label
    if (my $label = $self->char_data) {
      $cft->label($label);
    }

    if ($cft->complete) {
      my $type = $self->_cache_types($cft);
      $feature->type($type);
    }
  }
}

sub t_METHOD {
  my $self = shift;
  my $attrs = shift;
  my $feature = $self->{tmp}{current_feature} or return;
  my $cft = $self->{tmp}{type} ||= Bio::Das::Type->new();

  if ($attrs) {  # tag starts
    $cft->method($attrs->{id});
  }

  else {  # tag ends

    # possibly add a label
    if (my $label = $self->char_data) {
      $cft->method_label($label);
    }

    if ($cft->complete) {
      my $type = $self->_cache_types($cft);
      $feature->type($type);
    }

  }
}

sub t_START {
  my $self = shift;
  my $attrs = shift;
  my $feature = $self->{tmp}{current_feature} or return;
  $feature->start($self->char_data) unless $attrs;
}

sub t_END {
  my $self = shift;
  my $attrs = shift;
  my $feature = $self->{tmp}{current_feature} or return;
  $feature->stop($self->char_data) unless $attrs;
}

sub t_SCORE {
  my $self = shift;
  my $attrs = shift;
  my $feature = $self->{tmp}{current_feature} or return;
  $feature->score($self->char_data) unless $attrs;
}

sub t_ORIENTATION {
  my $self = shift;
  my $attrs = shift;
  my $feature = $self->{tmp}{current_feature} or return;
  $feature->orientation($self->char_data) unless $attrs;
}

sub t_PHASE {
  my $self = shift;
  my $attrs = shift;
  my $feature = $self->{tmp}{current_feature} or return;
  $feature->phase($self->char_data) unless $attrs;
}

sub t_GROUP {
  my $self = shift;
  my $attrs = shift;
  my $feature = $self->{tmp}{current_feature} or return;
  $feature->group($attrs->{id}) if $attrs;
}

sub t_LINK {
  my $self = shift;
  my $attrs = shift;
  my $feature = $self->{tmp}{current_feature} or return;
  if($attrs) {
      $feature->link( $attrs->{href} );
  } else {
      $feature->link_label( $self->char_data );
  }
}

sub t_NOTE {
  my $self = shift;
  my $attrs = shift;
  my $feature = $self->{tmp}{current_feature} or return;
  $feature->note($self->char_data) unless $attrs;
}

sub t_TARGET {
  my $self = shift;
  my $attrs = shift;
  my $feature = $self->{tmp}{current_feature} or return;
  $feature->target($attrs->{id},$attrs->{start},$attrs->{stop});
}

sub _cache_types {
  my $self = shift;
  my $type = shift;
  my $key = $type->_key;
  return $self->{cached_types}{$key} ||= $type;
}

# override for segmentation behavior
sub results {
  my $self = shift;
  my %r = $self->SUPER::results or return;

  # in array context, return the list of types
  return map { @{$_} } values %r if wantarray;

  # otherwise return ref to a hash
  return \%r;
}


1;
