use strict;
use warnings;
# XXX TODO:
# script
# FRIBIDI_PAR_ON
# text-out
# text-wrap

use Test::More;
use Prima::Test;
use Prima::Application;

my $w;
my $z;

my %glyphs;
my $high_unicode_char;

sub xtr($)
{
	my $xtr = shift;

	$xtr =~ tr[A-Z][\N{U+5d0}-\N{U+5e8}]; # hebrew
	# RTL(|/) ligates to %, with ZWJ (fribidi) or without (harfbuzz)
	$xtr =~ tr[|/%0][\x{627}\x{644}\x{fefb}\x{feff}]; 
	$xtr =~ tr[+-][\x{200d}\x{200c}];
	$xtr =~ s[\^][$high_unicode_char]g if defined $high_unicode_char;

	return $xtr;
}

sub glyphs($)
{
        my $str = xtr(shift);
        my %g;
        for my $c ( split //, $str ) {
	        my $k = $w-> text_shape($c);
                return unless $k;
                $g{$c} = $k->glyphs->[0];
        }
        return %glyphs = %g;
}

sub no_glyphs($)
{
        my $str = xtr(shift);
        my %g;
        for my $c ( split //, $str ) {
                $g{$c} = ord($c);
        }
        return %glyphs = %g;
}

sub glyphs_fully_resolved 
{
	return 0 unless scalar keys %glyphs;
	return 0 == scalar grep { !$_ } values %glyphs;
}

sub gmap($) { [ @glyphs{ split //, $_[0] } ] }

sub r { map { $_ | to::RTL } @_ }
sub R { reverse r @_ }

sub comp
{
	my ( $got, $exp, $name, $hexy, $text) = @_;

	if ( !$got && !$exp) { # undef and 0 are same, whatever
		ok(1, $name);
		return;
	}
	goto FAIL unless
		((ref($got) // '') eq 'ARRAY') &&
		((ref($exp) // '') eq 'ARRAY') &&
		@$got == @$exp;
	
	for ( my $i = 0; $i < @$got; $i++) {
		goto FAIL if ($got->[$i] // '<undef>') ne ($exp->[$i] // '<undef>');
	}
	ok(1, $name);
	return;

FAIL:
	ok(0, "$name {$text}");
	$got ||= ['<undef>'];
	$exp ||= ['<undef>'];
	$exp = [ map { defined($_) ? $_ : '<undef>' } @$exp ];
	$got = [ map { defined($_) ? $_ : '<undef>' } @$got ];
	if ( $hexy ) {
		@$got = map { /^\d+$/ ? (sprintf q(%x), $_) : $_ } @$got;
		@$exp = map { /^\d+$/ ? (sprintf q(%x), $_) : $_ } @$exp;
	} else {
		$_ = '-' . ($_ & ~to::RTL) for grep { /^\d+$/ && $_ & to::RTL } @$got;
		$_ = '-' . ($_ & ~to::RTL) for grep { /^\d+$/ && $_ & to::RTL } @$exp;
	}
	diag(sprintf("got [@$got], expected [@$exp]"));
}

sub t2
{
	my ( $text, $glyphs, $clusters, $name, %opt) = @_;

	my $orig_text   = $text;
	my $orig_glyphs = $glyphs;
	$text   = xtr $text;
	$glyphs = xtr $glyphs;
	$text =~ tr
		[<>=]
		#[\x{2067}\x{2066}\x{2069}]
		[\x{202B}\x{202a}\x{202c}]
		;

	$z = $w-> text_shape($text, %opt);
	return ok(0, "$name (undefined)") unless defined $z;
	return ok(0, "$name (unnecessary, retval=0)") unless $z;
	comp($z->glyphs, gmap $glyphs, "$name (glyphs)", 1, $orig_text);
	if ( defined $clusters ) {
		comp($z->clusters, $clusters, "$name (clusters)", 0, $_[0]);
		return;
	}

	my %rev = reverse %glyphs;
	my $v = join '',
		map {
			my $ofs  = $_ & ~to::RTL;
			my $char = sprintf("(%x)",$_);
		AGAIN:
			if ( $ofs >= 0 && $ofs <= length($orig_text)) {
				$char = substr($orig_text, $ofs, 1);
				if ( $char =~ /[\<\>\=]/ ) {
					$ofs++;
					goto AGAIN;
				}
				if ($_ & to::RTL) {
					$char = "(+$char)" if $char !~ /[A-Z\/\|\%0\+\-\.\s\?\`\<\>\^]/;
				} else {
					$char = "(-$char)" if $char !~ /[a-z\+\-\.\s\"\d\^]/;
				}
			}
			$char
		}
		@{$z->clusters // []};
	unless (is($v, $orig_glyphs, "$name (clusters)")) {
		my $got = $z->clusters // ['<undef>'];
		$got = [ map { defined($_) ? $_ : '<undef>' } @$got ];
		$_ = '-' . ($_ & ~to::RTL) for grep { /^\d+$/ && $_ & to::RTL } @$got;
		diag("got clusters: [@$got]");
	}

}

sub t
{
	my ( $text, $glyphs, $name, %opt) = @_;
	t2($text, $glyphs, undef, $name, %opt);
}

sub find_char
{
	my ($font, $char) = @_;
	$w->font($font);
	my @r = @{ $w->get_font_ranges };
	my $found;
	for ( my $i = 0; $i < @r; $i += 2 ) {
		my ( $l, $r ) = @r[$i, $i+1];
		$found = 1, last if $l <= $char && $r >= $char;
	}
	return $found;
}

sub find_high_unicode_char
{
	my ($font) = @_;
	$w->font($font);
	my @r = @{ $w->get_font_ranges };
	my @range;
	my $found;
	for ( my $i = 0; $i < @r; $i += 2 ) {
		my ( $l, $r ) = @r[$i, $i+1];
		next unless $r >= 0x10000;
		$l = 0x10000 if $l < 0x10000;
		push @range, $l .. $r;
		return \@range;
	}
	return undef;
}

sub find_high_unicode_font
{
	return 1 if find_high_unicode_char($w->font);
	my @f = @{$::application->fonts};
	for my $f ( @f ) {
		next unless $f->{vector};
		my $c = find_high_unicode_char($f);
		return $c if defined $c;
	}
	return undef;
}

# try to find font with given letters
# aim at highest standard, ie ttf/xft + scaling + bidi fonts
sub find_vector_font
{
	my $find_char = shift;
	return 1 if find_char($w->font, $find_char);

	my $got_rtl;
	my $found;
	my @f = @{$::application->fonts};

	# fontconfig fonts
	for my $f ( @f ) {
		next unless $f->{vector};
		next unless $f->{name} =~ /^[A-Z]/;
		next unless find_char($f, $find_char);
		$found = $f;
		$got_rtl = 1;
		goto FOUND;
	}

FOUND:
	$w->font->name($found->{name}) if $found;

	return $got_rtl;
}

sub check_noshape_nofribidi
{
	t('12', '12', 'ltr');
	t('12ABC', '12CBA', 'rtl in ltr');
	t('>AB', 'BA', 'bidi');
}

# very minimal support for bidi and X11 core fonts only
sub test_minimal
{
	ok(1, "test minimal");
	no_glyphs '12ABC';
	check_noshape_nofribidi();
}

# very minimal support for bidi with xft but no harfbuzz
sub test_glyph_mapping
{
	ok(1, "test glyph mapping without bidi");

        SKIP: {
                glyphs "12ABC";
		skip("text shaping is not available", 1) unless glyphs_fully_resolved;
		check_noshape_nofribidi();
        }
}

sub check_proper_bidi
{
	# http://unicode.org/reports/tr9/tr9-22.html
	SKIP : {
		glyphs ' ACDEIMNORUYSacdeghimnrs.?"`';
    		skip("not enough glyphs for proper bidi test", 1) unless glyphs_fully_resolved;
		t(
			'car means CAR.',
			'car means RAC.', 
			'example 1');
		t(
			'<car MEANS CAR.=',
			'.RAC SNAEM car',
			'example 2');
		t(
			'he said "<car MEANS CAR=."',
			'he said "RAC SNAEM car."',
			'example 3');
		t(
			'DID YOU SAY `>he said "<car MEANS CAR="=`?',
			'?`he said "RAC SNAEM car"` YAS UOY DID',
			'example 4',
			rtl => 1); # XXX not needed for autodetect
	}
}

sub test_fribidi
{
	ok(1, "test bidi");
	SKIP: {
		glyphs "12ABC|/%0";
		skip("text shaping is not available", 1) unless glyphs_fully_resolved;

		check_noshape_nofribidi();
		t('12ABC', 'CBA12', 'rtl in rtl', rtl => 1);
		t2('/|', '%0', [R(0,1)], 'arabic ligation with ZW nobreaker');
		t('|/', '/|', 'no arabic ligation');

		check_proper_bidi();
	}
}

sub test_shaping
{
	my ($found, $with_bidi) = @_;
	ok(1, "test shaping");

	SKIP: {
		skip("no vector fonts", 1) unless $found;

               	glyphs "12ABC";
		skip("text shaping is not available", 1) unless glyphs_fully_resolved;
		check_noshape_nofribidi();

		my $z = $w->text_shape('12', positions => 1);
		ok((4 == grep { m/^\d+$/ } @{$z->positions // []}), "positions are okay");
		ok((2 == grep { m/^\d+$/ } @{$z->advances  // []}), "advances are okay");

		if ( $with_bidi ) {
			t('12ABC', 'CBA12', 'rtl in rtl', rtl => 1);
		}

		SKIP: {
                	glyphs "|-/%";
			skip("arabic shaping is not available", 1) unless glyphs_fully_resolved;
			t('|/', '/|', 'no arabic ligation');
			t2('/|', '%', [r(0)], 'arabic ligation');
			if ( $with_bidi ) {
				t('/-|', '|-/', 'arabic non-ligation');
				check_proper_bidi();
			}
		}

		SKIP: {
			skip("no devanagari font", 1) unless find_vector_font(0x924);
			my $z = $w-> text_shape("\x{924}\x{94d}\x{928}");
			ok( $z && scalar(grep {$_} @{$z->glyphs}), 'devanagari shaping');
		}

		SKIP: {
 			skip("no khmer font", 1) unless find_vector_font(0x179f);
			my $z = $w-> text_shape("\x{179f}\x{17b9}\x{1784}\x{17d2}");
			ok( $z && scalar(grep {$_} @{$z->glyphs}), 'khmer shaping');
		}
	}
}

sub test_high_unicode
{
	ok(1, "high unicode");

	SKIP: {
		my $chars = find_high_unicode_font;
		skip("no fonts with characters above 0x10000", 1) unless $chars && @$chars;
		#splice(@$chars, 256); # win32 reports empty glyphs as available, but surely in 256 should be at least one valid glyph

		my $char;
		%glyphs = ();
        	for my $c (@$chars) {
		        my $k = $w-> text_shape(chr($c));
        	        next unless $k && $k->glyphs->[0];
			$high_unicode_char = chr($char = $c); # as ^
        	        $glyphs{$high_unicode_char} = $k->glyphs->[0];
			last;
        	}
		skip("text shaping is not available", 1) unless defined $char;
		t("^^", "^^", sprintf("found char U+%x in " . $w->font->name . " as glyph %x", $char, $glyphs{$high_unicode_char}));
	}
}

sub test_glyphs_out
{
	my $sum1 = shift;
	my $z = $w-> text_shape('12');

	$w-> clear;
	$w-> text_out( $z, 5, 5 );
	my $i = $w->image;
	$i->type(im::Byte);
	my $sum2 = $i->sum;
	is($sum2, $sum1, "glyphs plotting");
	
	$w-> clear;
	$z = $w-> text_shape('12', positions => 0);
	$w-> text_out( $w-> text_shape('12', positions => 0), 5, 5 );
	$i = $w->image;
	$i->type(im::Byte);
	my $sum3 = $i->sum;
	is($sum3, $sum1, "glyphs plotting with positions");

	$w-> clear;
	$w-> font-> set( height => 25, style => fs::Underlined, direction => -10 );
	$w-> text_out( "12", 5, 5 );
	$i = $w->image;
	$i->type(im::Byte);
	$sum1 = $i->sum;
	
	$z = $w-> text_shape('12');
	$w-> clear;
	$w-> text_out( $z, 5, 5 );
	$i = $w->image;
	$i->type(im::Byte);
	$sum2 = $i->sum;
	is($sum2, $sum1, "glyphs plotting 45 degrees");
	
	$w-> clear;
	$z = $w-> text_shape('12', positions => 0);
	$w-> text_out( $w-> text_shape('12', positions => 0), 5, 5 );
	$i = $w->image;
	$i->type(im::Byte);
	$sum3 = $i->sum;
	is($sum3, $sum1, "glyphs plotting 45 degrees with positions");
}

sub test_glyphs_wrap
{
	$w->font->size(12);
	my $z = $w-> text_shape('12', positions => 1);
	is( 2, scalar( @{ $z->glyphs // [] }), "text '12' resolved to 2 glyphs");

	my ($tw) = @{ $z->advances // [ $w->get_text_width('1') ] };

	my $r = $w-> text_wrap( $z, 0, tw::BreakSingle );
	is_deeply( $r, [], "warp with no fits");

	$r = $w-> text_wrap( $z, 0, tw::ReturnFirstLineLength );
	is( $r, 1, "tw::ReturnFirstLineLength");
	
	$r = $w-> text_wrap( $z, 0, tw::ReturnChunks );
	is_deeply( $r, [0,1,1,1], "tw::ReturnChunks");
	
	$r = $w-> text_wrap( $z, 0, 0 );
	is( scalar(@$r), 2, "wrap: split to 2 pieces");
	is_deeply( $r->[0]->glyphs, [ $z->glyphs->[0] ], "glyphs 1");
	is_deeply( $r->[1]->glyphs, [ $z->glyphs->[1] ], "glyphs 2");
	is_deeply( $r->[0]->clusters, [ $z->clusters->[0] ], "clusters 1");
	is_deeply( $r->[1]->clusters, [ $z->clusters->[1] ], "clusters 2");
	if ( $z-> advances ) {
		is_deeply( $r->[0]->advances, [ $z->advances->[0] ], "advances 1");
		is_deeply( $r->[1]->advances, [ $z->advances->[1] ], "advances 2");
		is_deeply( $r->[0]->positions, [ @{$z->positions}[0,1] ], "positions 1");
		is_deeply( $r->[1]->positions, [ @{$z->positions}[2,3] ], "positions 2");
	}
}

sub test_drawing
{ SKIP: {
	glyphs "12";
	skip("glyph drawing is not available", 1) unless glyphs_fully_resolved;

	$w-> backColor(cl::Black);
	$w-> color(cl::White);
	$w-> font-> set( height => 25, style => fs::Underlined );
	$w-> clear;
	$w-> text_out( "12", 5, 5 );
	my $i = $w->image;
	$i->type(im::Byte);
	my $sum1 = $i->sum;
	skip("text drawing on bitmap is not available", 1) unless $sum1;
	
	my $z = $w-> text_shape('12');
	skip("shaping is not available", 1) unless $z;

	test_glyphs_out($sum1);
	test_glyphs_wrap();
}}

sub run_test
{
	my $unix = shift;

	$w = Prima::DeviceBitmap-> create( type => dbt::Pixmap, width => 32, height => 32);
	my $found = find_vector_font(0x5d0); # A-Z mapped to hebrew

	my $z = $w-> text_shape( "1" );
	plan skip_all => "Shaping is not available" if defined $z && $z eq '0';

	my %opt;
	$opt{fribidi} = 1 if Prima::Application->get_system_value(sv::FriBidi);
	if ( $unix ) {
		%opt = (%opt, map { $_ => 1 } split ' ', Prima::Application->sys_action('shaper'));
		if ( $opt{harfbuzz} && $opt{xft}) {
			test_shaping($found, $opt{fribidi});
		} elsif ( $opt{fribidi}) {
			test_fribidi;
		} elsif ( $opt{xft}) {
			test_glyph_mapping;
		} else {
			test_minimal;
		}
	} else {
		test_shaping($found, $opt{fribidi});
	}
	test_high_unicode;
	test_drawing;
}

if ( Prima::Application-> get_system_info->{apc} == apc::Unix ) {
	if ( @ARGV ) {
		run_test(1);
	} else {
		my %options = Prima::options();
		my @opt = grep { m/^no-(fribidi|harfbuzz|xft)$/ } sort keys %options;
		for ( my $i = 0; $i < 2 ** @opt; $i++) {
			my @xopt = map { "--$_" } @opt[ grep { $i & (1 << $_) } 0..$#opt ];
			my @inc  = map { "-I$_" } @INC;
			for ( split "\n", `$^X @inc $0 @xopt TEST 2>&1`) {
				if (m/^(ok|not ok)\s+\d+(.*)/) {
					my ( $ok, $info ) = ( $1 eq 'ok', $2);
					if ( $info =~ /# skip (.*)/) {
						SKIP: { skip("(@xopt) $1", 1) };
					} else {
						ok($ok, "(@xopt) $info");
					}
				} elsif ( m/# SKIP (.*)/) {
					SKIP: { skip("(@xopt) $1", 1) };
				} elsif ( !m/^\d+\.\.\d+/) {
					warn "$_\n";
				}
			}
		}
	}
} else {
	run_test(0);
}

done_testing;

