package EBox::Gettext;

use Locale::gettext;
use EBox::Config;
use Encode qw(:all);

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

	@ISA = qw(Exporter);
	@EXPORT = qw{ __ __x settextdomain langs };
	%EXPORT_TAGS = ( DEFAULT => \@EXPORT );
	@EXPORT_OK = qw();
	$VERSION = EBox::Config::version;
}

sub settextdomain # (domain)
{
	$domain = shift;
	textdomain($domain);
	bindtextdomain($domain, EBox::Config::locale());
}

sub __ # (text)
{
	my $string = gettext(shift);
	_utf8_on($string);
	return $string;
}

sub __x # (text, %variables)
{
	my ($msgid, %vars) = @_;
	my $string = gettext($msgid);
	_utf8_on($string);
	return __expand($string, %vars);
}

sub __expand # (translation, %arguments)
{
	my ($translation, %args) = @_;

	my $re = join '|', map { quotemeta $_ } keys %args;
	$translation =~ s/\{($re)\}/defined $args{$1} ? $args{$1} : "{$1}"/ge;
	return $translation;
}

use utf8;
my $langs;
$langs->{'es_ES.UTF-8'} = 'Castellano';
$langs->{'ca_ES.UTF-8'} = 'Català';
$langs->{'C'} = 'English';
$langs->{'fr_FR.UTF-8'} = 'Français';
no utf8;

sub langname # (locale)
{
	my ($locale) = @_;

	return $langs->{$locale};
}

sub langs
{
	return $langs;
}

1;
