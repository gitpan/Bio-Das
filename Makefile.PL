use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
	      NAME	 => 'Bio::Das',
	      VERSION_FROM => 'Das.pm', # finds $VERSION
	      PREREQ_PM    => {
			       Compress::Zlib => 1.0,
			       HTML::Parser => 3.0,
			       LWP          => 5.0,
			       MIME::Base64 => 2.12,
			      }
	     );
