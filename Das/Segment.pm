package Bio::Das::Segment;

# $Id: Segment.pm,v 1.2 2002/08/31 23:32:53 lstein Exp $
use strict;
use overload '""' => 'asString';
*refseq = \&ref;
*stop   = \&end;

sub new {
  my $pack = shift;
  my ($ref,$start,$stop,$version) = @_;
  bless {ref    =>$ref,
	 start  =>$start,
	 end    =>$stop,
	 version=>$version},$pack;
}

sub ref      {
  my $self = shift;
  my $d    = $self->{ref};
  $self->{ref} = shift if @_;
  $d;
}
sub start      {
  my $self = shift;
  my $d    = $self->{start};
  $self->{start} = shift if @_;
  $d;
}
sub end      {
  my $self = shift;
  my $d    = $self->{end};
  $self->{end} = shift if @_;
  $d;
}
sub version      {
  my $self = shift;
  my $d    = $self->{version};
  $self->{version} = shift if @_;
  $d;
}
sub size     {
  my $self = shift;
  my $d    = $self->{size};
  $self->{size} = shift if @_;
  $d ||= $self->end-$self->start+1;
  $d;
}
sub class      {
  my $self = shift;
  my $d    = $self->{class};
  $self->{class} = shift if @_;
  $d;
}
sub orientation {
  my $self = shift;
  my $d    = $self->{orientation};
  $self->{orientation} = shift if @_;
  $d;
}
sub subparts {
  my $self = shift;
  my $d    = $self->{subparts};
  $self->{subparts} = shift if @_;
  $d;
}
sub asString {
  my $self = shift;
  my $string = $self->{ref};
  return "global" unless $string;
  $string .= ":$self->{start}" if defined $self->{start};
  $string .= ",$self->{end}"   if defined $self->{end};
}

1;

