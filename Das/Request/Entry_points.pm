package Bio::Das::Request::Entry_points;
# $Id: Entry_points.pm,v 1.3 2003/12/06 00:15:39 lstein Exp $
# this module issues and parses the entry_points command, with the ref argument

use strict;
use Bio::Das::DSN;
use Bio::Das::Request;
use Bio::Das::Util 'rearrange';

use vars '@ISA';
@ISA = 'Bio::Das::Request';

sub new {
  my $pack = shift;
  my ($dsn,$ref,$callback) = rearrange(['dsn',
					'ref',
					'callback',
				       ],@_);

  return $pack->SUPER::new(-dsn=>$dsn,
			   -callback=>$callback,
			   -args   => {ref => $ref}
			  );
}

sub command { 'entry_points' }

# top-level tag
sub t_DASEP {
  my $self  = shift;
  my $attrs = shift;
  if ($attrs) {  # section is starting
    $self->clear_results;
  }
  $self->{current_ep} = undef;
}

sub t_ENTRY_POINTS {
# nothing to do there
}

# segment is beginning
sub t_SEGMENT {
  my $self  = shift;
  my $attrs = shift;
  if ($attrs) {    # segment section is starting
    warn "in entry_points:",join ',',%$attrs;
    $self->{current_ep} = Bio::Das::Segment->new($attrs->{id},
						 $attrs->{start}||1,
						 $attrs->{stop}||$attrs->{size},
						 $attrs->{version}||'1.0');
    $self->{current_ep}->size($attrs->{size});
    $self->{current_ep}->class($attrs->{class});
    $self->{current_ep}->orientation($attrs->{orientation});
    $self->{current_ep}->subparts(1) if defined $attrs->{subparts} 
      && $attrs->{subparts} eq 'yes';
  }
  else {  # reached the end of the segment, so push result
    $self->add_object($self->{current_ep});
  }
}

1;

