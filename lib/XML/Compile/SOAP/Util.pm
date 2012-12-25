# Copyrights 2007-2012 by [Mark Overmeer].
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 2.00.
use warnings;
use strict;

package XML::Compile::SOAP::Util;
use vars '$VERSION';
$VERSION = '2.34';

use base 'Exporter';

my @soap10 = qw/SOAP11HTTP WSDL11HTTP WSDL11MIME SOAP11ENV/;
my @soap11 = qw/SOAP11ENV SOAP11ENC SOAP11NEXT SOAP11HTTP WSDL11SOAP/;
my @wsdl11 = qw/WSDL11 WSDL11SOAP WSDL11HTTP WSDL11MIME WSDL11SOAP12/;
my @daemon = qw/MSEXT/;
my @xop10  = qw/XOP10 XMIME10 XMIME11/;

our @EXPORT_OK = (@soap10, @soap11, @wsdl11, @daemon, @xop10);
our %EXPORT_TAGS =
  ( soap10 => \@soap10
  , soap11 => \@soap11
  , wsdl11 => \@wsdl11
  , daemon => \@daemon
  , xop10  => \@xop10
  );


use constant SOAP11 => 'http://schemas.xmlsoap.org/soap/';
use constant
  { SOAP11ENV       => SOAP11. 'envelope/'
  , SOAP11ENC       => SOAP11. 'encoding/'
  , SOAP11NEXT      => SOAP11. 'actor/next'
  , SOAP11HTTP      => SOAP11. 'http'
  };


use constant WSDL11 => 'http://schemas.xmlsoap.org/wsdl/';
use constant
  { WSDL11SOAP      => WSDL11. 'soap/'
  , WSDL11HTTP      => WSDL11. 'http/'
  , WSDL11MIME      => WSDL11. 'mime/'
  , WSDL11SOAP12    => WSDL11. 'soap12/'
  };
 

use constant MSEXT          => SOAP11ENV;


use constant
  { XOP10           => 'http://www.w3.org/2004/08/xop/include'
  , XMIME10         => 'http://www.w3.org/2004/11/xmlmime'
  , XMIME11         => 'http://www.w3.org/2005/05/xmlmime'
  };

1;
