#########
# Author: jc3
# Maintainer: jc3
# Created: 2003-09-17
# Last Modified: 2003-09-17
# Provides DAS features for Trace file Information.

package Bio::Das::ProServer::SourceAdaptor::trace;
=head1 AUTHOR

Jody Clements <jc3@sanger.ac.uk>.

based on modules by 

Roger Pettett <rmp@sanger.ac.uk>.

Copyright (c) 2003 The Sanger Institute

This library is free software; you can redistribute it a nd/or modify
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
use Time::HiRes qw(gettimeofday);

sub init{
  my $self = shift;
  $self->{'capabilities'} = {
			     'features' => '1.0',
			     'stylesheet' => '1.0',
			    };
  $self->{'link'} = "http://trace.ensembl.org/perl/traceview?traceid=";
  $self->{'linktxt'} = "more information";
}

sub length{
  my ($self,$seg) = @_;
  if ($seg !~ /^(10|20|(1?[1-9])|(2?[12])|[XY])$/i){
    #get contig coordinates
    return;
  }
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
		       <CATEGORY id="trace">
		        <TYPE id="Forward">
		         <GLYPH>
		          <FARROW>
		           <HEIGHT>2</HEIGHT>
		           <BGCOLOR>black</BGCOLOR>
                           <FGCOLOR>red</FGCOLOR>
		           <FONT>sanserif</FONT>
		           <BUMP>0</BUMP>
		          </FARROW>
		         </GLYPH>
		        </TYPE>
		        <TYPE id="Reverse">
		         <GLYPH>
		          <RARROW>
		           <HEIGHT>2</HEIGHT>
		           <BGCOLOR>black</BGCOLOR>
                           <FGCOLOR>black</FGCOLOR>
		           <FONT>sanserif</FONT>
                           <BUMP>0</BUMP>
		          </RARROW>
		         </GLYPH>
		        </TYPE>
		       </CATEGORY>
		      </STYLESHEET>
		     </DASSTYLE>\n);

  return $response;
}

sub build_features{
  my  $t0 = gettimeofday;
  
  my ($self,$opts) = @_;
  my $segid  = $opts->{'segment'};
  my $start = $opts->{'start'};
  my $end   = $opts->{'end'};

  warn "Building started for: ",$segid," at ",$t0,"\n";
#####
#  if $end - $start = too big then return some sort of average 
#  density across the area selected. this should reduce the load
#  times when a large sequence is requested. Maybe anything greater
#  than a kilobase.
#####
  my @features = ();
  if (!$end){
    return @features;
  }

my $query = qq(SELECT 	DISTINCT (ms.contig_match_start + ssm.start_coordinate -1) as start_coord,
	(ms.contig_match_end + ssm.start_coordinate -1) as end_coord,
	ms.snp_rea_id_read as read_id,
	sr.readname,
	ms.is_revcomp as orientation
FROM	chrom_seq cs,
	seq_seq_map ssm,
	snp_sequence ss,
	mapped_seq ms,
	snp_read sr
WHERE	cs.database_seqname = '$segid'
AND	cs.id_chromseq = ssm.id_chromseq
AND	ssm.sub_sequence = ss.id_sequence
AND	ms.id_sequence = ss.id_sequence
AND	ms.snp_rea_id_read = sr.id_read
AND     cs.is_current = 1
AND     ( (ms.is_revcomp = 0 and 
            ms.contig_match_start between $start-10000-ssm.start_coordinate and $end-ssm.start_coordinate+1 AND
            ms.contig_match_end > $start-ssm.start_coordinate+1 ) or (
          ms.is_revcomp = 1 and 
            ms.contig_match_start between $start-ssm.start_coordinate+1     and $end-ssm.start_coordinate+10000 AND
            ms.contig_match_end < $end-ssm.start_coordinate+1))
order by start_coord);

my $t1 = gettimeofday;
warn "Query begun ",$t1 - $t0,"\n";

my $trace = $self->transport->query($query);

my $t2 = gettimeofday;
warn "Query ended ",$t2 - $t0,"\n";
warn "Query duration ",$t2 -$t1,"\n";
warn "Feature building begins ",$t2 - $t0,"\n";

  for my $trace (@$trace){
    my $url = $self->{'link'};
    my $link = $url . $trace->{'READNAME'};
    my $ori = ($trace->{'ORIENTATION'} == 1)?"-":"+";
    my $type = ($trace->{'ORIENTATION'} == 1)?"Forward":"Reverse";
    my $start = $trace->{'START_COORD'}; 
    my $end = $trace->{'END_COORD'};

    if ($start > $end){
      ($start,$end) = ($end,$start);
    }
      
    push @features, {
		     'id'           => $trace->{'READNAME'},
		     'method'       => "trace",
		     'type'         => $type,
		     'ori'          => $ori,
		     'start'        => $start,
		     'end'          => $end,
		     'link'        => $link,
		     'linktxt'     => $self->{'linktxt'},
		     'typecategory' => "trace",
		    };
  }

my $t4 = gettimeofday;
warn "Feature building done ",$t4 - $t0,"\n";
warn "feature build duration ",$t4 - $t2,"\n";

  return @features;
}
1;
