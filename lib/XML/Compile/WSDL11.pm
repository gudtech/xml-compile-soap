# Copyrights 2007-2012 by [Mark Overmeer].
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 2.00.
use warnings;
use strict;

package XML::Compile::WSDL11;
use vars '$VERSION';
$VERSION = '2.34';

use base 'XML::Compile::Cache';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';

use XML::Compile             ();      
use XML::Compile::Util       qw/pack_type unpack_type/;
use XML::Compile::SOAP::Util qw/:wsdl11/;
use XML::Compile::SOAP::Extension;

use XML::Compile::SOAP::Operation  ();
use XML::Compile::Transport  ();

use List::Util               qw/first/;

XML::Compile->addSchemaDirs(__FILE__);
XML::Compile->knownNamespace(&WSDL11 => 'wsdl.xsd');


sub init($)
{   my ($self, $args) = @_;
    $args->{schemas} and panic "new(schemas) option removed in 0.78";
    my $wsdl = delete $args->{top};

    local $args->{any_element}      = 'ATTEMPT';
    local $args->{any_attribute}    = 'ATTEMPT'; # not implemented
    local $args->{allow_undeclared} = 1;

    $self->SUPER::init($args);

    $self->{index}   = {};

    $self->prefixes(wsdl => WSDL11, soap => WSDL11SOAP, http => WSDL11HTTP);

    # next modules should change into an extension as well...
    $_->can('_initWSDL11') && $_->_initWSDL11($self)
        for XML::Compile::SOAP::Operation->registered;

    XML::Compile::SOAP::Extension->wsdl11Init($self, $args);

    $self->declare
      ( READER      => 'wsdl:definitions'
      , key_rewrite => 'PREFIXED(wsdl,soap,http)'
      , hook        => {type => 'wsdl:tOperation', after => 'ELEMENT_ORDER'}
      );

    $self->{XCW_dcopts} = {};

    $self->importDefinitions(WSDL11);

    $self->addWSDL($_) for ref $wsdl eq 'ARRAY' ? @$wsdl : $wsdl;
    $self;
}

sub schemas(@) { panic "schemas() removed in v2.00, not needed anymore" }

#--------------------------


sub compileAll(;$$)
{   my ($self, $need, $usens) = @_;
    $self->SUPER::compileAll($need, $usens)
        if !$need || $need ne 'CALLS';

    $self->compileCalls
        if !$need || $need eq 'CALLS';
    $self;
} 


sub compileCalls(@)
{   my ($self, %args) = @_;

    my @ops = $self->operations
      ( service => delete $args{service}
      , port    => delete $args{port}
      , binding => delete $args{binding}
      );

    $self->{XCW_ccode} ||= {};
    foreach my $op (@ops)
    {   my $name  = $op->name;
        my @opts  = %args;
        my $dopts = $self->{XCW_dcopts} || {};
        push @opts, ref $dopts eq 'ARRAY' ? @$dopts : %$dopts;

        $self->{XCW_ccode}{$name} ||= $op->compileClient(@opts);
    }

    $self->{XCW_ccode};
}

#--------------------------


sub call($@)
{   my ($self, $name) = (shift, shift);

    my $codes = $self->{XCW_ccode}
        or error __x"you can only use call() after compileCalls()";

    my $call  = $codes->{$name}
        or error __x"operation {name} is not known", name => $name;
    
    $call->(@_);
}

#--------------------------


sub _learn_prefixes($)
{   my ($self, $node) = @_;

    my $namespaces = $self->prefixes;
  PREFIX:
    foreach my $ns ($node->getNamespaces)  # learn preferred ns
    {   my ($prefix, $uri) = ($ns->getLocalName, $ns->getData);
        next if !defined $prefix || $namespaces->{$uri};

        if(my $def = $self->prefix($prefix))
        {   next PREFIX if $def->{uri} eq $uri;
        }
        else
        {   $self->prefixes($prefix => $uri);
            next PREFIX;
        }

        $prefix =~ s/0?$/0/;
        while(my $def = $self->prefix($prefix))
        {   next PREFIX if $def->{uri} eq $uri;
            $prefix++;
        }
        $self->prefixes($prefix => $uri);
    }
}

sub addWSDL($)
{   my ($self, $data) = @_;
    defined $data or return ();

    defined $data or return;
    my ($node, %details) = $self->dataToXML($data);
    defined $node or return $self;

    $node->localName eq 'definitions' && $node->namespaceURI eq WSDL11
        or error __x"root element for WSDL is not 'wsdl:definitions'";

    $self->importDefinitions($node, details => \%details);
    $self->_learn_prefixes($node);

    my $spec = $self->reader('wsdl:definitions')->($node);
    my $tns  = $spec->{targetNamespace}
        or error __x"WSDL sets no targetNamespace";

    # WSDL 1.1 par 2.1.1 says: WSDL def types each in own name-space
    my $index     = $self->{index};

    # silly WSDL structure
    my $toplevels = $spec->{gr_wsdl_anyTopLevelOptionalElement} || [];

    foreach my $toplevel (@$toplevels)
    {   my ($which, $def) = %$toplevel;        # always only one
        $which =~ s/^wsdl_(service|message|binding|portType)$/$1/
            or next;

        $index->{$which}{pack_type $tns, $def->{name}} = $def;

        if($which eq 'service')
        {   foreach my $port ( @{$def->{port} || []} )
            {   $index->{port}{pack_type $tns, $port->{name}} = $port;
            }
        }
    }

    # no service block when only one port
    unless($index->{service})
    {   # only from this WSDL, cannot use collective $index
        my @portTypes = map { $_->{wsdl_portType} || () } @$toplevels;
        @portTypes==1
            or error __x"no service definition so needs 1 portType, found {nr}"
                 , nr => scalar @portTypes;

        my @bindings = map { $_->{wsdl_binding} || () } @$toplevels;
        @bindings==1
            or error __x"no service definition so needs 1 binding, found {nr}"
                 , nr => scalar @bindings;

        my $binding  = pack_type $tns, $bindings[0]->{name};
        my $portname = $portTypes[0]->{name};
        my $servname = $portname;
        $servname =~ s/Service$|(?:Service)?Port(?:Type)?$/Service/i
             or $servname .= 'Service';

        my %port = (name => $portname, binding => $binding
           , soap_address => {location => 'http://localhost'} );

        $index->{service}{pack_type $tns, $servname}
            = { name => $servname, wsdl_port => [ \%port ] };
        $index->{port}{pack_type $tns, $portname} = \%port;
    }
#warn "INDEX: ",Dumper $index;
    $self;
}


sub namesFor($)
{   my ($self, $class) = @_;
    keys %{shift->index($class) || {}};
}


# new options, then also add them to the list in compileClient()

sub operation(@)
{   my $self = shift;
    my $name = @_ % 2 ? shift : undef;
    my %args = (name => $name, @_);

    #
    ## Service structure
    #

    my $service   = $self->findDef(service => delete $args{service});

    my $port;
    my @ports     = @{$service->{wsdl_port} || []};
    my @portnames = map {$_->{name}} @ports;
    if(my $portname = delete $args{port})
    {   $port = first {$_->{name} eq $portname} @ports;
        error __x"cannot find port `{portname}', pick from {ports}"
            , portname => $portname, ports => join("\n    ", '', @portnames)
           unless $port;
    }
    elsif(@ports==1)
    {   $port = shift @ports;
    }
    else
    {   error __x"specify port explicitly, pick from {portnames}"
            , portnames => join("\n    ", '', @portnames);
    }

    # get plugin for operation # {
    my $address   = first { $_ =~ m/address$/ } keys %$port
        or error __x"no address provided in service {service} port {port}"
             , service => $service->{name}, port => $port->{name};

    if($address =~ m/^{/)      # }
    {   my ($ns)  = unpack_type $address;

        warning __"Since v2.00 you have to require XML::Compile::SOAP11 explicitly"
            if $ns eq WSDL11SOAP;

        error __x"ports of type {ns} not supported (not loaded?)", ns => $ns;
    }

#use Data::Dumper;
#warn Dumper $port, $self->prefixes;
    my ($prefix)  = $address =~ m/(\w+)_address$/;
    $prefix
        or error __x"port address not prefixed; probably need to add a plugin";

    my $opns      = $self->findName("$prefix:");
    my $opclass   = XML::Compile::SOAP::Operation->plugin($opns);
    unless($opclass)
    {   my $pkg = $opns eq WSDL11SOAP   ? 'SOAP11'
                : $opns eq WSDL11SOAP12 ? 'SOAP12'
                : $opns eq WSDL11HTTP   ? 'SOAP10'
                :                         undef;

        if($pkg)
        {   error __x"add 'use XML::Compile::{pkg}' to your script", pkg=>$pkg;
        }
        else
        {   notice __x"ignoring unsupported namespace {ns}", ns => $opns;
            return;
        }
    }

    $opclass->can('_fromWSDL11')
        or error __x"WSDL11 not supported by {class}", class => $opclass;

    #
    ## Binding
    #

    my $bindtype  = $port->{binding}
        or error __x"no binding defined in port '{name}'"
               , name => $port->{name};

    my $binding   = $self->findDef(binding => $bindtype);

    my $type      = $binding->{type}  # get portTypeType
        or error __x"no type defined with binding `{name}'"
               , name => $bindtype;

    my $portType  = $self->findDef(portType => $type);
    my $types     = $portType->{wsdl_operation}
        or error __x"no operations defined for portType `{name}'"
               , name => $type;

    my @port_ops  = map {$_->{name}} @$types;

    $name       ||= delete $args{operation};
    my $port_op;
    if(defined $name)
    {   $port_op = first {$_->{name} eq $name} @$types;
        error __x"no operation `{op}' for portType {pt}, pick from{ops}"
          , op => $name, pt => $type, ops => join("\n    ", '', @port_ops)
            unless $port_op;
    }
    elsif(@port_ops==1)
    {   $port_op = shift @$types;
        $name    = $port_op->{name};
    }
    else
    {   error __x"multiple operations in portType `{pt}', pick from {ops}"
            , pt => $type, ops => join("\n    ", '', @port_ops)
    }

    my @bindops   = @{$binding->{wsdl_operation} || []};
    my $bind_op   = first {$_->{name} eq $name} @bindops;
    $bind_op
        or error __x"cannot find bind operation for {name}", name => $name;

    # This should be detected while parsing the WSDL because the order of
    # input and output is significant (and lost), but WSDL 1.1 simplifies
    # our life by saying that only 2 out-of 4 predefined types can actually
    # be used at present.

    my @order = map { (unpack_type $_)[1] } @{$port_op->{_ELEMENT_ORDER}};

    my ($first_in, $first_out);
    for(my $i = 0; $i<@order; $i++)
    {   $first_in  = $i if !defined $first_in  && $order[$i] eq 'input';
        $first_out = $i if !defined $first_out && $order[$i] eq 'output';
    }

    my $kind
      = !defined $first_in     ? 'notification-operation'
      : !defined $first_out    ? 'one-way'
      : $first_in < $first_out ? 'request-response'
      :                          'solicit-response';

    #
    ### message components
    #

    my $operation = $opclass->_fromWSDL11
     ( name      => $name,
     , kind      => $kind

     , service   => $service
     , serv_port => $port
     , binding   => $binding
     , bind_op   => $bind_op
     , portType  => $portType
     , port_op   => $port_op

     , wsdl      => $self
     , action    => $args{action}
     );
 
    $operation;
}


sub compileClient(@)
{   my $self = shift;
    unshift @_, 'operation' if @_ % 2;
    my $op   = $self->operation(@_) or return ();
    $op->compileClient(@_);
}

#---------------------


sub declare($$@)
{   my ($self, $need, $names, @opts) = @_;
    my $opts = @opts==1 ? shift @opts : \@opts;
    $opts = [ %$opts ] if ref $opts eq 'HASH';

    $need eq 'OPERATION'
        or $self->SUPER::declare($need, $names, @opts);

    foreach my $name (ref $names eq 'ARRAY' ? @$names : $names)
    {   # checking existence of opname is expensive here
        # and may be problematic with multiple bindings.
        $self->{XCW_dcopts}{$name} = $opts;
    }

    $self;
}

#--------------------------


sub index(;$$)
{   my $index = shift->{index};
    @_ or return $index;

    my $class = $index->{ (shift) }
       or return ();

    @_ ? $class->{ (shift) } : $class;
}


sub findDef($;$)
{   my ($self, $class, $name) = @_;
    my $group = $self->index($class)
        or error __x"no definitions for `{class}' found", class => $class;

    if(defined $name)
    {   return $group->{$name} if exists $group->{$name};  # QNAME

        if($name =~ m/\:/)                                 # PREFIXED
        {   my $qname = $self->findName($name);
            return $group->{$qname} if exists $group->{$qname};
        }

        if(my $q = first { (unpack_type $_)[1] eq $name } keys %$group)
        {   return $group->{$q};
        }

        error __x"no definition for `{name}' as {class}, pick from:{groups}"
          , name => $name, class => $class
          , groups => join("\n    ", '', sort keys %$group);
    }

    return values %$group
        if wantarray;

    return (values %$group)[0]
        if keys %$group==1;

    my @alts = map $self->prefixed($_), sort keys %$group;
    error __x"explicit selection required: pick one {class} from {alts}"
      , class => $class, alts => join("\n    ", '', @alts);
}


sub operations(@)
{   my ($self, %args) = @_;
    my @ops;
    $args{produce} and die "produce option removed in 0.81";

    foreach my $service ($self->findDef('service'))
    {
        next if $args{service} && $args{service} ne $service->{name};

        foreach my $port (@{$service->{wsdl_port} || []})
        {
            next if $args{port} && $args{port} ne $port->{name};

            my $bindtype = $port->{binding}
                or error __x"no binding defined in port '{name}'"
                      , name => $port->{name};
            my $binding  = $self->findDef(binding => $bindtype);

            next if $args{binding} && $args{binding} ne $binding->{name};

            my $type     = $binding->{type}
                or error __x"no type defined with binding `{name}'"
                    , name => $bindtype;

            foreach my $operation ( @{$binding->{wsdl_operation}||[]} )
            {   push @ops, $self->operation
                  ( service   => $service->{name}
                  , port      => $port->{name}
                  , binding   => $bindtype
                  , operation => $operation->{name}
                  , portType  => $type
                  );
            }
        }
    }

    @ops;
}


sub endPoint(@)
{   my ($self, %args) = @_;
    my $service   = $self->findDef(service => delete $args{service});

    my $port;
    my @ports     = @{$service->{wsdl_port} || []};
    my @portnames = map {$_->{name}} @ports;
    if(my $portname = delete $args{port})
    {   $port = first {$_->{name} eq $portname} @ports;
        error __x"cannot find port `{portname}', pick from {ports}"
            , portname => $portname, ports => join("\n    ", '', @portnames)
           unless $port;
    }
    elsif(@ports==1)
    {   $port = shift @ports;
    }
    else
    {   error __x"specify port explicitly, pick from {portnames}"
            , portnames => join("\n    ", '', @portnames);
    }

    foreach my $k (keys %$port)
    {   return $port->{$k}{location} if $k =~ m/address$/;
    }

    ();
}


sub printIndex(@)
{   my $self = shift;
    my $fh   = @_ % 2 ? shift : select;
    my @args = @_;

    my %tree;
    $tree{'service '.$_->serviceName}
         {$_->version.' port '.$_->portName . ' (binding '.$_->bindingName.')'}
         {$_->name} = $_
         for $self->operations(@args);

    foreach my $service (sort keys %tree)
    {   $fh->print("$service\n");
        foreach my $port (sort keys %{$tree{$service}})
        {   $fh->print("    $port\n");
            foreach my $op (sort keys %{$tree{$service}{$port}})
            {   $fh->print("        $op\n");
            }
        }
    }
}


sub explain($$$@)
{   my ($self, $opname, $format, $direction, @opts) = @_;
    my $op = $self->operation($opname, @opts)
        or error __x"explain operation {name} not found", name => $opname;
    $op->explain($self, $format, $direction, @opts);
}

#--------------------------------


1;
