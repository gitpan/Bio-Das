#########
# Author: jc3
# Maintainer: jc3
# Created: 2003-06-20
# Last Modified: 2003-06-20
# Provides DAS features for SNP information.

package Bio::Das::ProServer::SourceAdaptor::snp;

=head1 AUTHOR

Jody Clements <jc3@sanger.ac.uk>.

based on modules by 

Roger Pettett <rmp@sanger.ac.uk>.

Copyright (c) 2003 The Sanger Institute

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut
BEGIN {
  my $root = $ENV{'ENS_ROOT'};
  if(!defined $ENV{'ENSEMBL_SPECIES'} || $ENV{'ENSEMBL_SPECIES'} eq ""){
    print STDERR qq(No species defined... default to Homo_sapiens\n);
    $ENV{'ENSEMBL_SPECIES'} = "Homo_sapiens" ;
  }
  print STDERR qq(species = $ENV{'ENSEMBL_SPECIES'}\n);
  unshift(@INC,"$root/modules");
  unshift(@INC,"$root/ensembl/modules");
  unshift(@INC,"$root/ensembl-draw/modules");
  unshift(@INC,"$root/ensembl-map/modules");
  unshift(@INC,"$root/ensembl-compara/modules");
  unshift(@INC,"$root/ensembl-external/modules");
  unshift(@INC,"$root/conf");
  unshift(@INC,"$root/perl");
  unshift(@INC,"$root/bioperl-live");
}

use strict;
use EnsWeb;
use EnsEMBL::DB::Core;
use base qw(Bio::Das::ProServer::SourceAdaptor);



sub init{
  my $self = shift;
  $self->{'capabilities'} = {
			     'features' => '1.0',
			     'stylesheet' => '1.0',
			    };
  $self->{'link'} = "http://intweb.sanger.ac.uk/cgi-bin/humace/snp_report.pl?snp=";
  $self->{'linktxt'} = "more information";
}

#######
# gets rid of chromosome coordinates if multiple segments are present
#
#sub init_segments{
#  my ($self,$segments) = @_;
#  if (scalar @$segments > 1 && (grep {$_ =~ /^AL\d{6}/i} @$segments)){
#    @$segments = grep {$_ !~ /^(10|20|(1?[1-9])|(2?[12])|[XY])/i} @$segments;
#  }
#}

sub length{
  my ($self,$seg) = @_;
  if ($seg !~ /^(10|20|(1?[1-9])|(2?[12])|[XY])$/i){
    if ($seg !~/^\w+\.\w+\.\w+\.\w+$/i){
      #get contig coordinates
      if (!$self->{'_length'}->{$seg}){
	my $databases = &EnsEMBL::DB::Core::get_databases('core');
	my $ca = $databases->{'core'}->get_CloneAdaptor();
	my $clone = $ca->fetch_by_name($seg);
	my $contigs = $clone->get_all_Contigs();
	if(@$contigs == 1){
	  $self->{'_length'}->{$seg} = $contigs->[0]->length();
	}
      }
      return $self->{'_length'}->{$seg};
    }
    return;
  }
  #get chromosome coordinates
  if (!$self->{'_length'}->{$seg}){
    my $databases = &EnsEMBL::DB::Core::get_databases('core');
    my $ca = $databases->{'core'}->get_ChromosomeAdaptor();
    my $chromosome = $ca->fetch_by_chr_name($seg);
    $self->{'_length'}->{$seg} = $chromosome->length();
  }
  return $self->{'_length'}->{$seg};
}


sub das_stylesheet{
  my ($self) = @_;

  my $response = qq(<!DOCTYPE DASSTYLE SYSTEM "http://www.biodas.org/dtd/dasstyle.dtd">
<DASSTYLE>
<STYLESHEET version="1.0">
   <CATEGORY id="snp">
    <TYPE id="External Verified">
      <GLYPH>
        <BOX>
          <FGCOLOR>red</FGCOLOR>
          <FONT>sanserif</FONT>
          <BGCOLOR>black</BGCOLOR>
        </BOX>
      </GLYPH>
    </TYPE>
    <TYPE id="Sanger Verified">
      <GLYPH>
        <BOX>
          <FGCOLOR>green</FGCOLOR>
          <FONT>sanserif</FONT>
          <BGCOLOR>black</BGCOLOR>
        </BOX>
      </GLYPH>
    </TYPE>
    <TYPE id="Two-Hit">
      <GLYPH>
        <BOX>
          <FGCOLOR>blue</FGCOLOR>
          <FONT>sanserif</FONT>
          <BGCOLOR>black</BGCOLOR>
        </BOX>
      </GLYPH>
    </TYPE>
    <TYPE id="default">
      <GLYPH>
        <BOX>
          <FGCOLOR>darkolivegreen</FGCOLOR>
          <FONT>sanserif</FONT>
          <BGCOLOR>black</BGCOLOR>
        </BOX>
      </GLYPH>
    </TYPE>
  </CATEGORY>
</STYLESHEET>
</DASSTYLE>\n);

  return $response;
}

sub build_features{
  my ($self,$opts) = @_;
  my $segid       = $opts->{'segment'};
  my $start       = $opts->{'start'};
  my $end         = $opts->{'end'};
  my $restriction = "";
  my $query       = "";
  my @features    = ();

  if (defined $start && !$end){
    return @features;
  }

  if (defined $start && defined $end){
    $restriction = qq(AND     ms.POSITION
                      BETWEEN	($start - ssm.START_COORDINATE - 99)
	              AND	($end - ssm.START_COORDINATE + 1));

  }

  if ($segid =~ /^(10|20|(1?[1-9])|(2?[12])|[XY])$/i){
    #get chromosome coordinates
    $query = qq(SELECT 	distinct
	(ms.position + ssm.START_COORDINATE -1) as snppos,
	ms.id_snp as snp_id,
	ss.default_name as snp_name,
	ss.confirmation_status as status
FROM 	chrom_seq cs,
	seq_seq_map ssm,
	mapped_snp ms,
	snp_summary ss
WHERE 	cs.DATABASE_SEQNAME='$segid'
AND     cs.is_current = 1
AND 	cs.ID_CHROMSEQ = ssm.ID_CHROMSEQ
AND 	ms.ID_SEQUENCE = ssm.SUB_SEQUENCE
AND	ss.id_snp = ms.id_snp

$restriction
ORDER BY SNPPOS);

  }
#  elsif ($segid !~ /^\w+\.\w+\.\w+\.\w+$/i){
#    #get contig coordinates
#    $query = qq(select distinct snp_name.snp_name as SNP_NAME,
#		(1 +(clone_seq_map.CONTIG_ORIENTATION * (mapped_snp.position -
#		clone_seq_map.START_COORDINATE))) as SNPPOS,
#		snp.is_confirmed as STATUS,
#		mapped_snp.id_snp as SNP_ID
#		from snp_name,
#		mapped_snp,
#		clone_seq_map,
#		snp,
#		clone_seq
#		where (mapped_snp.position between  clone_seq_map.START_COORDINATE and
#		clone_seq_map.END_COORDINATE
#		or mapped_snp.position between clone_seq_map.END_COORDINATE and
#		clone_seq_map.START_COORDINATE)
#		and  mapped_snp.id_sequence =  clone_seq_map.id_sequence
#		and clone_seq.DATABASE_SEQNAME = '$segid'
#		and clone_seq_map.ID_CLONESEQ = clone_seq.ID_CLONESEQ
#		and mapped_snp.id_sequence =  clone_seq_map.id_sequence
#		and mapped_snp.id_snp = snp.id_snp
#		and snp.id_snp = snp_name.id_snp
#		and snp_name.snp_name_type=1
#		order by SNPPOS);
#  }
  else{
    return @features;
  }

 my $snp = $self->transport->query($query);


for my $snp (@$snp){
  my $url = $self->{'link'};
  my $link = $url . $snp->{'SNP_NAME'};
  my $type = "Unknown";
  if ($snp->{'STATUS'} == 1){
    $type = "Sanger Verified";
  }
  elsif($snp->{'STATUS'} == 2){
    $type = "External Verified";
  }
  elsif($snp->{'STATUS'} == 3){
    $type = "Two-Hit";
  }
  push @features, {
		   'id'      => $snp->{'SNP_NAME'},
		   'type'    => $type,
		   'method'  => "snp",
		   'start'   => $snp->{'SNPPOS'},
		   'end'     => $snp->{'SNPPOS'},
		   'ori'     => "0",
		   'link'    => $link,
		   'linktxt' => $self->{'linktxt'},
		   'typecategory' => "snp",
		  };
}
  return @features;
}

1;
