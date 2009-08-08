#####################################################################
#
# A library to validate XML files against schemas.
#
# File: common/lib/ValidSchema.pm
# License: GPL
# License URL: http://www.gnu.org/copyleft/gpl.html
#
# Authors:
#  Ricardo Munoz <ricardo.munoz at hispalinux.es>
#
# Created: 2004 06 01 by EXUS
#
######################################################################

package EBox::Schema;

use XML::Xerces;

# boolean
# validateXMLFile($) 
# $ a string that contains the XML file to validate.
#
# returns true if the XML file its according to the schema or undef if not.

sub validate($) {
	# FIXME - remove this line when schemas have been written for all
	# modules
	return 1;
	#create a new parser
	my $file = shift;
	my $val_to_use = XML::Xerces::SchemaValidator->new();
	my $parser = XML::Xerces::SAXParser->new($val_to_use);
	$parser->setValidationScheme ($XML::Xerces::AbstractDOMParser::Val_Auto);
	$parser->setErrorHandler(XML::Xerces::PerlErrorHandler->new());
	$parser->setDoNamespaces(1);
	$parser->setDoSchema(1);

	eval {$parser->parse ($file)};

	if ($@) {
	#TODO how to manage an error parsing the XML file.
		return undef;
	}
	
	return 1;
}

1;
