package Bio::Das::Request::Dsn;
# $Id: Dsn.pm,v 1.2 2003/05/22 19:46:55 avc Exp $
# this module issues and parses the dsn command, with no arguments

use strict;
use Bio::Das::DSN;
use Bio::Das::Request;
use Bio::Das::Util 'rearrange';

use vars '@ISA';
@ISA = 'Bio::Das::Request';

sub new {
  my $pack = shift;
  my ($base,$callback) = rearrange(['dsn',
				    'callback'
				   ],@_);

  return $pack->SUPER::new(-dsn=>$base,-callback=>$callback);
}

sub command { 'dsn' }

# top-level tag
sub t_DASDSN {
  my $self  = shift;
  my $attrs = shift;
  if ($attrs) {  # section is starting
    $self->clear_results;
  }
  $self->{current_dsn} = undef;
}

# the beginning of a dsn
sub t_DSN {
  my $self = shift;
  my $attrs = shift;
  if ($attrs) {  # tag starts
    $self->{current_dsn} = Bio::Das::DSN->new($self->dsn->base);
  } else {
    $self->add_object($self->{current_dsn});
  }
}

sub t_SOURCE {
  my $self  = shift;
  my $attrs = shift;
  my $dsn = $self->{current_dsn} or return;
  if ($attrs) {
    $dsn->id($attrs->{id});
  } else {
    my $name = $self->trim($self->{char_data});
    $dsn->name($name);
  }
}

sub t_MAPMASTER {
  my $self  = shift;
  my $attrs = shift;
  my $dsn = $self->{current_dsn} or return;
  if ($attrs) {
    ; # do nothing here
  } else {
    my $name = $self->char_data;
    $dsn->master($name);
  }
}

sub t_DESCRIPTION {
  my $self  = shift;
  my $attrs = shift;
  my $dsn = $self->{current_dsn} or return;
  if ($attrs) {
    ; # do nothing here
  } else {
    my $name = $self->{char_data};
    $dsn->description($name);
  }
}

1;

