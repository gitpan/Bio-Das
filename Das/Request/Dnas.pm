package Bio::Das::Request::Dnas;
# $Id: Dnas.pm,v 1.3 2003/05/22 19:46:55 avc Exp $
# this module issues and parses the types command, with arguments -dsn, -segment, -categories, -enumerate

use strict;
use Bio::Das::Segment;
use Bio::Das::Request;
use Bio::Das::Util 'rearrange';

use vars '@ISA';
@ISA = 'Bio::Das::Request';

sub new {
  my $pack = shift;
  my ($dsn,$segments,$callback) = rearrange([['dsn','dsns'],
					     ['segment','segments'],
					     'callback'
					    ],@_);

  my $self = $pack->SUPER::new(-dsn => $dsn,
			       -callback => $callback,
			       -args => {
					 segment   => $segments,
					} );

  $self;
}

sub command { 'dna' }

sub t_DASDNA {
  my $self = shift;
  my $attrs = shift;
  if ($attrs) {
    $self->clear_results;
  }
  delete $self->{tmp};
}

sub t_SEQUENCE {
  my $self = shift;
  my $attrs = shift;
  if ($attrs) {    # segment section is starting
    $self->{tmp}{current_segment} = Bio::Das::Segment->new($attrs->{id},$attrs->{start},$attrs->{stop},$attrs->{version});
  }

  else {  # reached the end of the segment, so push result
    $self->{tmp}{current_dna} =~ s/\s//g;
    $self->add_object($self->{tmp}{current_segment},$self->{tmp}{current_dna});
  }

}

sub t_DNA {
  my $self = shift;
  my $attrs = shift;

  if ($attrs) {  # start of tag
    $self->{tmp}{current_dna}     = '';
  }

  else {
    my $dna = $self->char_data;
    $self->{tmp}{current_dna} .= $dna;
  }
}

# override for "better" behavior
sub results {
  my $self = shift;
  my %r = $self->SUPER::results or return;

  # in array context, return the list of dnas
  return values %r if wantarray;

  # otherwise return ref to a hash in which the keys are segments and the values
  # are DNAs
  return \%r;
}


1;
