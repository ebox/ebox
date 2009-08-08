package EBox::Gettext;

use Locale::gettext;
use EBox::Config;
use Encode qw(:all);

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

	@ISA = qw(Exporter);
	@EXPORT = qw{ __ __x settextdomain };
	%EXPORT_TAGS = ( DEFAULT => \@EXPORT );
	@EXPORT_OK = qw();
	$VERSION = EBox::Config::version;
}

sub settextdomain($){
	$domain = shift;
	textdomain($domain);
	bindtextdomain($domain, EBox::Config::locale);
}

sub __($){
	my $string = gettext(shift);
	_utf8_on($string);
	return $string;
}

sub __x($%){
	my ($msgid, %vars) = @_;
	my $string = gettext($msgid);
	_utf8_on($string);
	return __expand($string, %vars);
}

sub __expand($%){
	my ($translation, %args) = @_;

	my $re = join '|', map { quotemeta $_ } keys %args;
	$translation =~ s/\{($re)\}/defined $args{$1} ? $args{$1} : "{$1}"/ge;
	return $translation;
}

1;
