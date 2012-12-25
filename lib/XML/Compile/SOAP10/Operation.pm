# Copyrights 2007-2012 by [Mark Overmeer].
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 2.00.
use warnings;
use strict;

package XML::Compile::SOAP10::Operation;
use vars '$VERSION';
$VERSION = '2.34';

use base 'XML::Compile::SOAP::Operation';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';
use List::Util  'first';

use XML::Compile::Util       qw/pack_type unpack_type/;
use XML::Compile::SOAP::Util qw/:soap10/;
use XML::Compile::SOAP::Extension;

our $VERSION;         # OODoc adds $VERSION to the script
$VERSION ||= 'undef';

XML::Compile->knownNamespace
  ( &WSDL11HTTP => 'wsdl-http.xsd'
  , &WSDL11MIME => 'wsdl-mime.xsd'
  );
__PACKAGE__->register(WSDL11HTTP, undef);

# client/server object per schema class, because initiation options
# can be different.  Class reference is key.
my (%soap11_client, %soap11_server);


sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);
    $self;
}

sub _initWSDL11($)
{   my ($class, $wsdl) = @_;

    trace "initialize SOAP10 operations for WSDL11";

    $wsdl->importDefinitions(WSDL11HTTP, element_form_default => 'qualified');
    $wsdl->importDefinitions(WSDL11MIME, element_form_default => 'qualified');
    $wsdl->prefixes
      ( http => WSDL11HTTP
      , mime => WSDL11MIME
      );

    $wsdl->declare(READER => [ "http:binding" ]);
}

sub _fromWSDL11(@)
{   my ($class, %args) = @_;

    # Extract the SOAP11 specific information from a WSDL11 file. There are
    # half a zillion parameters.

    $args{schemas}   = $args{wsdl};
    $args{endpoints} = $args{serv_port}{http_address}{location};

    my $wb           = $args{binding}{http_binding} || {};
    $args{verb}      = $wb->{verb}   || 'POST';
    $class->SUPER::new(%args);
}

#-------------------------------------------


sub http_method { shift->{verb} }
sub version()   { 'SOAP10' }
sub serverClass { undef }
sub clientClass { undef }

#-------------------------------------------


sub explain($$$@)
{   my ($self, $schema, $format, $dir, %args) = @_;
    error "Cannot explain HTTP use: don't know myself";
}

1;
