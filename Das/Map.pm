package Bio::Das::Map;
# $Id: Map.pm,v 1.2 2002/11/22 18:05:35 lstein Exp $

use strict;
use vars '@ISA','$VERSION';
use Bio::Root::RootI;
use Bio::Location::Simple;

@ISA = 'Bio::Root::RootI';
$VERSION = '1.00';

use constant REF     => 0;
use constant OFFSET  => REF +1;
use constant LEN     => OFFSET + 1;

use constant SRC_SEG  => 0;
use constant TARG_SEG => SRC_SEG+1;
use constant FLIPPED  => TARG_SEG + 1;


my %DATA;

# coordinate mapping service

sub new {
  my $class = shift;
  my $name  = shift;
  my $self = bless \(my $fly);
  $DATA{$self}{name} = $name || $self;
  $self;
}

sub DESTROY {
  my $self = shift;
  delete $DATA{$self};
}

sub name {
  my $self = shift;
  my $d = $DATA{$self}{name};
  $DATA{$self}{name} = shift if @_;
  $d;
}

sub clip {
  my $self = shift;
  my $d = $DATA{$self}{clip};
  $DATA{$self}{clip} = shift if @_;
  $d;
}

sub add_segment {
  my $self = shift;
  my ($src,$target) = @_;  # either [ref,start,stop,strand] triplets or Bio::LocationI objects
  my ($src_ref,$src_offset,$src_len,$src_strand)     = $self->_location2offset($src);
  my ($targ_ref,$targ_offset,$targ_len,$targ_strand) = $self->_location2offset($target);
  my $src_seg  = [$src_ref,$src_offset,$src_len];
  my $targ_seg = [$targ_ref,$targ_offset,$targ_len];
  my $alignment = [$src_seg,$targ_seg,$src_strand ne $targ_strand];
  push @{$DATA{$self}{segments}{$src_ref}},$src_seg;
  push @{$DATA{$self}{segments}{$targ_ref}},$targ_seg;
  push @{$DATA{$self}{alignments}{$src_ref}{child}},$alignment;
  push @{$DATA{$self}{alignments}{$targ_ref}{parent}},$alignment;
}

sub resolve {
  my $self = shift;
  my @result = $self->_resolve($self->_location2offset(@_));
  return $self->_offset2location(\@result);
}

sub project {
  my $self     = shift;
  my ($location,$target) = @_;
  my @location = $self->_location2offset($location);
  return $self->_offset2location([$self->_map2map(@location,$target,'parent'),
				  $self->_map2map(@location,$target,'child')]
				);
}

sub expand_segments {
  my $self = shift;
  my ($ref,$offset,$len,$strand)     = $self->_location2offset(@_);
  my @parents  = $self->super_segments($ref,$offset,$len,$strand);
  my @children = $self->sub_segments($ref,$offset,$len,$strand);
  my ($me)     = $self->_offset2location([[$ref,$offset,$len,$strand]]);
  return (@parents,$me,@children);
}

# return mapping of all subsegments
sub sub_segments {
  my $self = shift;
  my @result = $self->_segments($self->_location2offset(@_),'child');
  return $self->_offset2location(\@result);
}

# return mapping of all subsegments
sub super_segments {
  my $self = shift;
  my @result = $self->_segments($self->_location2offset(@_),'parent');
  return $self->_offset2location(\@result);
}

sub _segments {
  my $self = shift;
  my ($ref,$offset,$len,$strand,$relationship) = @_;  # relationship = 'parent', 'child'
  my $alignments  = $self->_lookup_alignment($relationship,$ref,$offset,$len,$strand);
  my @result;
  for my $a (@$alignments) {
    my ($src,$targ) = $relationship eq 'parent' ? @{$a}[1,0] : @{$a}[0,1];
    my ($t_ref,$t_offset,$t_len,$t_strand) = 
      $self->_map_and_clip([$offset,$len,$strand],$src,$targ,$a->[2]);
    push @result,[$t_ref,$t_offset,$t_len,$t_strand];
    push @result,$self->_segments($t_ref,$t_offset,$t_len,$t_strand,$relationship);  # recurse
  }
  @result;
}

# map given segment to all top-level coordinates by following parents
sub _resolve {
  my $self = shift;
  my ($ref,$offset,$len,$strand) = @_;

  my $alignments = $self->_lookup_alignment('parent',$ref,$offset,$len,$strand);
  my @result;

  push @result,[$ref,$offset,$len,$strand] unless @$alignments;

  for my $a (@$alignments) {
    my ($p_ref,$p_offset,$p_len,$p_strand) = $self->_map_and_clip([$offset,$len,$strand],$a->[1],$a->[0],$a->[2]);
    push @result,$self->_resolve($p_ref,$p_offset,$p_len,$p_strand); #recursive invocation
  }
  @result;
}

sub _map2map {
  my $self = shift;
  my ($ref,$offset,$len,$strand,$target,$relationship) = @_;  # relationship = 'parent', 'child'

  my $alignments  = $self->_lookup_alignment($relationship,$ref,$offset,$len,$strand);
  my @result;

  for my $a (@$alignments) {
    my ($src,$targ) = $relationship eq 'parent' ? @{$a}[1,0] : @{$a}[0,1];
    my ($p_ref,$p_offset,$p_len,$p_strand) = $self->_map_and_clip([$offset,$len,$strand],$src,$targ,$a->[2]);
    if ($p_ref eq $target) {
      push @result,[$p_ref,$p_offset,$p_len,$p_strand];
    } else {  # keep searching recursively
      push @result,$self->_map2map($p_ref,$p_offset,$p_len,$p_strand,$target,$relationship); #recursive invocation
    }
  }
  @result;
}

sub _offset2location {
  my $self = shift;
  my $array = shift;
  return map {
    my ($ref,$offset,$len,$strand) = @$_;
    Bio::Location::Simple->new(-seq_id  => $ref,
			       -start  => $offset+1,
			       -end    => $offset+$len,
			       -strand => $strand);
  } @$array;

}

sub lookup_segments {
  my $self   = shift;
  my $result = $self->_lookup_segments(@_);
  map {
    my ($ref,$offset,$len) = @$_;
    Bio::Location::Simple->new(-seq_id  => $ref,
			       -start  => $offset+1,
			       -end    => $offset+$len,
			       -strand => +1);
  } @$result;
}


sub map_segment {
  my $self = shift;
  my ($src,$dest) = @_;    # map source range onto destination
}

sub abs_segment {
  my $self = shift;
  my $src  = shift;        # map to topmost coordinates
}

# simple lookup of segments overlapping requested range
sub _lookup_segments {
  my $self    = shift;
  my ($ref,$offset,$len,$strand)     = $self->_location2offset(@_);

  my $search_space = $DATA{$self}{segments}{$ref} or return;
  my @result;
  for my $candidate (@$search_space) {
    next unless $candidate->[OFFSET]+$candidate->[LEN] > $offset
      && $candidate->[OFFSET] < $offset + $len;
    push @result,$candidate;
  }
  return \@result;
}

sub _lookup_alignment {
  my $self = shift;
  my ($relationship,$ref,$offset,$len,$strand) = @_;
  my @result;

  my $search_space = $DATA{$self}{alignments}{$ref}{$relationship};
  for my $candidate (@$search_space) {
    my $seg = $relationship eq 'parent' ? $candidate->[1] : $candidate->[0];
    next unless $seg->[OFFSET]+$seg->[LEN] > $offset
      && $seg->[OFFSET] < $offset + $len;
    push @result,$candidate;
  }
  \@result;
}

sub _map_and_clip {
  my $self = shift;
  my ($range,$source,$dest,$flip) = @_;
  my ($offset,$len,$strand) = @$range;
  my $clip = $self->clip;

  $offset = $flip ? $dest->[OFFSET] + $source->[OFFSET] - $offset
                  : $offset + $dest->[OFFSET]-$source->[OFFSET];

  if ($clip) {
    $offset  = $dest->[OFFSET]                       if $offset < $dest->[OFFSET];
    $len     = $dest->[OFFSET]+$dest->[LEN]-$offset  if $offset+$len > $dest->[OFFSET]+$dest->[LEN];
  }

  return ($dest->[REF],$offset,$len,$flip ? -$strand : $strand);
}

sub _location2offset {
  my $self  = shift;
  return ($_[0],$_[1]-1,$_[2]-$_[1]+1,+1)    if @_ == 3;  # (ref,offset,len)
  return ($_[0],$_[1]-1,$_[2]-$_[1]+1,$_[3]) if @_ >= 4;  # (ref,offset,len,strand)

  my $thing = shift;

  my ($ref,$offset,$len,$strand);
  if (ref($thing) eq 'ARRAY') {
    my ($id,$start,$end,$str) = @$thing;
    $offset  = $start - 1;
    $len     = $end - $start + 1;
    $strand  = +1 unless defined $strand;
    $ref     = $id;
    $strand  = $str || +1;
  }

  elsif (ref($thing) && $thing->isa('Bio::LocationI')) {
    $ref    = $thing->seq_id;
    $offset = $thing->start - 1;
    $len    = $thing->end - $thing->start + 1;
    $strand = $thing->strand || +1;
  }

  else {
    $self->throw('not a valid location object or array');
  }

  return ($ref,$offset,$len,$strand);
}


1;
