#########
# Author: rmp
# Maintainer: rmp
# Created: 2003-06-03
# Last Modified: 2003-06-03
#
# Pro source/parser configuration
#
package Bio::Das::ProServer::Config;

=head1 AUTHOR

Roger Pettett <rmp@sanger.ac.uk>.

Based on AGPServer by

Tony Cox <avc@sanger.ac.uk>.

Copyright (c) 2003 The Sanger Institute

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut

use strict;
use Bio::Das::ProServer::SourceAdaptor;
use Sys::Hostname;

sub new {
  my $class = shift;
  my $self = {
	      'hostname' => &Sys::Hostname::hostname(),
	      'port'     => '9000',
	      'adaptors' => {
			     'mysimple'     => {
						'adaptor'       => 'simple',
						'state'         => 'off',
						'transport'     => 'file',
						'filename'      => '/path/to/genelist.txt',
						'baseurl'       => 'http://www.mysite.org/datascript?id=',
						'type'          => 'gene',
						'feature_query' => 'field0 lceq "%s"',
						'unique'        => 1, # optional
					       },
			     'swissprot'    => {
						'adaptor'       => 'swissprot',
						'state'         => 'off',
						'transport'     => 'getzc',
						'host'          => 'srs.server.org',
						'port'          => 20204,
					       },
			     'interpro'     => {
						'adaptor'       => 'interpro',
						'state'         => 'off',
						'transport'     => 'getz',
						'getz'          => '/usr/local/bin/getz',
					       },
			     'ncbi33'       => {
						'adaptor'       => 'agp',
						'state'         => 'off',
						'transport'     => 'dbi',
						'host'          => 'localhost',
						'port'          => '3306',
						'username'      => 'mydbuser',
						'dbname'        => 'mydbname',
						'password'      => 'mydbpass',
						'tablename'     => 'tmp_agp_ncbi33',
					       },
    			     'myembl'       => {
					        'state'         => 'off',
					        'adaptor'       => 'bioseq',
					        'transport'     => 'bioseqio',
					        'filename'      => '/path/to/data/ECAPAH02.embl',
					        'format'        => 'embl',
					        'index'         => 'bdb',           # optional (Bio::DB::Flat)
					        'dbname'        => 'an_embl_db',    # optional (Bio::DB::Flat)
					        'dbroot'        => '/tmp'           # optional (Bio::DB::Flat)
					      },
			    },
	     };
  
  bless $self,$class;
  return $self;
}

sub port {
  my $self = shift;
  ($self->{'port'}) = $self->{'port'} =~ /([0-9]+)/;
  return $self->{'port'};
}

sub host {
  my $self = shift;
  ($self->{'hostname'}) = $self->{'hostname'} =~ /([a-zA-Z0-9\/\-_\.]+)/;
  return $self->{'hostname'};
}

sub adaptors {
  my $self = shift;
  return map { $self->adaptor($_); } grep { ($self->{'adaptors'}->{$_}->{'state'} || "off") eq "on"; } keys %{$self->{'adaptors'}};
}

sub adaptor {
  my ($self, $dsn) = @_;

  if($dsn && $self->{'adaptors'}->{$dsn}->{'state'} eq "on") {
    my $adaptortype = "Bio::Das::ProServer::SourceAdaptor::".$self->{'adaptors'}->{$dsn}->{'adaptor'};
    eval "require $adaptortype";
    warn $@ if($@);
    $self->{'adaptors'}->{$dsn}->{'obj'} ||= $adaptortype->new({
								'dsn'      => $dsn,
								'config'   => $self->{'adaptors'}->{$dsn},
								'hostname' => $self->{'hostname'},
								'port'     => $self->{'port'},
							       });
    return $self->{'adaptors'}->{$dsn}->{'obj'};

  } else {
    $self->{'_genadaptor'} ||= Bio::Das::ProServer::SourceAdaptor->new({
									'hostname' => $self->{'hostname'},
									'port'     => $self->{'port'},
									'config'   => $self,
								       });
    return $self->{'_genadaptor'};
  }
}

sub transport {
  my ($self, $dsn) = @_;
  return $self->{'adaptors'}->{$dsn}->{'transport'} || "unknown";
}

sub knows {
  my ($self, $dsn) = @_;
  return (exists $self->{'adaptors'}->{$dsn} && $self->{'adaptors'}->{$dsn}->{'state'} eq "on");
}

sub das_version {
  return "DAS/1.50";
}

1;
