package Bio::Das::DSN;
# $Id: DSN.pm,v 1.4 2003/05/22 19:46:55 avc Exp $

use strict;
use overload '""'  => 'url',
             'eq' => 'eq';

sub new {
  my $package = shift;
  my ($base, $id,$name,$master,$description) = @_;
  if (!$id && $base =~ m!(.+/das)/([^/]+)!) {
    $base = $1;
    $id = $2;
  }
  return bless {
		base => $base,
		id => $id,
		name => $name,
		master => $master,
		description => $description,
	       },$package;
}

sub set_authentication{
  my ($self, $user, $pass) = @_;
  my $base = $self->base;

  #Strip any old authentication from URI, and replace
  $base =~ s#^(.+?://)(.*?@)?#$1$user:$pass@#;  

  $self->base($base);
}

sub url {
  my $self = shift;
  return defined $self->{id} ? "$self->{base}/$self->{id}" : $self->{base};
}

sub base {
  my $self = shift;
  my $d = $self->{base};
  $self->{base} = shift if @_;
  $d;
}

sub id {
  my $self = shift;
  my $d = $self->{id};
  $self->{id} = shift if @_;
  $d;
}

sub name {
  my $self = shift;
  my $d = $self->{name};
  $self->{name} = shift if @_;
  $d;
}

sub description {
  my $self = shift;
  my $d = $self->{description};
  $self->{description} = shift if @_;
  $d;
}

sub master {
  my $self = shift;
  my $d = $self->{master};
  $self->{master} = shift if @_;
  $d;
}

sub eq {
  my $self = shift;
  my $other = shift;
  return $self->url eq $other->url;
}

1;
