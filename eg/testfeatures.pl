#!/usr/local/bin/perl

use lib './blib/lib','../blib/lib';
use Bio::Das;

my $das = Bio::Das->new(15);  # timeout of 15 sec
# $das->debug(1);
# $das->proxy('http://kato.lsjs.org/');

# this callback will print the features as they are reconstructed
my $callback = sub {
  my $feature = shift;
  my $segment = $feature->segment;
  my ($start,$stop) = ($feature->start,$feature->stop);
  print "$segment => $feature ($start,$stop)\n";
};

my $response = $das->features(-dsn => 'http://genome.cse.ucsc.edu/cgi-bin/das/hg8',  #hg7,8 have problems
			      -segment => [
					   'chr22:13000000,13100000',
					   'chr1:1000000,1020000'
					  ],
			      -category => 'transcription',
			      -callback => $callback
			     );
die $response->error unless $response->is_success;

my $results = $response->results;

for my $seg (keys %$results) {
  my @features = @{$results->{$seg}};
  print join " ",$seg,@features,"\n";
}
