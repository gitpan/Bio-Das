#########
# Author: rmp
# Maintainer: rmp
# Created: 2003-05-20
# Last Modified: 2003-05-27
# Builds DAS features from COSMIC Cancer database
#
package Bio::Das::ProServer::SourceAdaptor::cosmic;

=head1 AUTHOR

Roger Pettett <rmp@sanger.ac.uk>.

Copyright (c) 2003 The Sanger Institute

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut

use strict;
use vars qw(@ISA);
use Bio::Das::ProServer::SourceAdaptor;
@ISA = qw(Bio::Das::ProServer::SourceAdaptor);

sub init {
  my $self                = shift;
  $self->{'dsn'}          = "cosmic";
  $self->{'capabilities'} = {
			     'features' => '1.0',
			    };
}

sub length {
  my ($self, $seg) = @_;

  if(!$self->{'_length'}->{$seg}) {
    my $ref = $self->transport->query(qq(SELECT plength AS length
					 FROM   locus
					 WHERE  swissprot_id = '$seg'));
    if(scalar @$ref) {
      $self->{'_length'}->{$seg} = @{$ref}[0]->{'length'};
    }
  }
  return $self->{'_length'}->{$seg};
}

sub build_features {
  my ($self, $opts) = @_;
  my $spid    = $opts->{'segment'};
  my $start   = $opts->{'start'};
  my $end     = $opts->{'end'};
  my $qbounds = "";
  $qbounds    = qq(AND a.aa_start <= '$end' AND a.aa_start+a.aa_length >= '$start') if($start && $end);
  my $query   = qq(SELECT a.id AS id, a.aa_start AS start, a.aa_length AS length
		   FROM   allele a,sample_allele sa, sample s, locus l
		   WHERE  a.id           = sa.allele_id
		   AND    sa.sample_id   = s.id
		   AND    s.locus_id     = l.id
		   AND    l.swissprot_id = '$spid' $qbounds
		   GROUP BY aa_start,aa_length);
  my $ref = $self->transport->query($query);
  my @features = ();

  for my $row (@{$ref}) {
    my $start = $row->{'start'};
    my $end   = $row->{'start'} + $row->{'length'} -1;
    ($start, $end) = ($end, $start) if($start > $end);
    
    #########
    # safety catch. throw stuff which looks like it's out of bounds
    #
    next if($start > $self->length($spid));
    
    push @features, {
		     'id'     => $row->{'id'},
		     'type'   => "cgpace",
		     'method' => "cgpace",
		     'start'  => $start,
		     'end'    => $end,
		    };
  }

  return @features;
}

1;
