#!/usr/bin/perl

use lib './blib/lib','../blib/lib';
use Bio::Das;

my $das = Bio::Das->new(15);  # timeout of 15 sec
$das->debug(0);
# $das->proxy('http://kato.lsjs.org/');

# this callback will print the features as they are reconstructed
my $callback = sub {
  my $feature = shift;
  my $segment = $feature->segment;
  my ($start,$stop) = ($feature->start,$feature->stop);
  print "$segment => $feature ($start,$stop)\n";
};

my $response = $das->features(-dsn => 'http://brie2.cshl.org:8081/db/misc/das/freeman',  #hg7,8 have problems
			      -segment => [
					   'chrx',
					   'Z96810.1.1.99682',
					   'Z96810',
					  ],
			      -callback => $callback
			     );
die $response->error unless $response->is_success;

my $results = $response->results;

for my $seg (keys %$results) {
  my @features = @{$results->{$seg}};
  print join " ",$seg,@features,"\n";
}
