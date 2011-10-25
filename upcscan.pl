#!/usr/bin/perl -w
use strict;
use Tk;
use Tk::JPEG;
use POE;
use Getopt::Long;
##
## http://perlmeister.com/forum/viewtopic.php?t=3596&sid=59d9cb0bda64235bda70315d6e9031e8
use POE::Loop::Tk ;
##
use LWP::UserAgent::POE;
use Net::Amazon;
use Net::Amazon::Request::UPC;
use Net::Amazon::Request::EAN;
use MIME::Base64;
use Rose::DB::Object::Loader;
use Log::Log4perl qw(:easy);

my $amz_token = '1DG7JR3MJN78X61PP3G2';
my $amz_secret = 'x9MGAcSCXx0njaY7YhKHNem8nOGWq0e3wElUncIV';

my $personal_base_name = 'personal_catalog_tp.dat' ; ## default
my $show_help = 'Usage: upcscan.pl [-b nazwa-bazy]';

GetOptions("help=s" => \$show_help, "base=s" => \$personal_base_name);

my @MODES = qw(books music dvd);

my $UA = LWP::UserAgent::POE->new();

my $loader = Rose::DB::Object::Loader->new(
  db_dsn => "dbi:SQLite:dbname=$personal_base_name",
  db_options   => {
    AutoCommit => 1, RaiseError => 1 },
);

$loader->make_classes();

my $top = $poe_main_window;
$top->configure(-title => "UPC Reader (base: $personal_base_name)",
                -background=> "#a2b2a3");
$top->geometry("500x300");

my $FOOTER = $top->Label();
$FOOTER->configure(-text => "Scan next item");

my $BYWHO = $top->Label();
my $UPC   = $top->Label();

## cf. http://www.ibm.com/developerworks/aix/library/au-perltkmodule2/
##my $MODE  = $top->Label(-text =>'Item mode')->pack(); ## >>tp>>
my $MODE  = $top->Label();
##$MODE->configure(-text => "Item mode");
##$MODE->title("Item mode");
my $current_amz_cat = $MODES[0]; ## domyślnym jest pierwszy
foreach(@MODES) { 
  $MODE->Radiobutton( 
      -text => $_, 
      -value=> $_, 
      -variable => \$current_amz_cat,
      -command => sub {
	print STDERR "*** Current mode is: $current_amz_cat \n";
      } )->pack(-side => 'left', -expand => '1', -fill => "x" )
}

my $PHOTO = $top->Photo(-format => 'jpeg');
my $photolabel = 
             $top->Label(-image => $PHOTO);
my $entry = $top->Entry(
            -textvariable => \my $UPC_VAR);

my $PRODUCT = $top->Label();

$entry->focus();

for my $w ($entry, $photolabel, $PRODUCT, $BYWHO, $UPC, $MODE, $FOOTER) {
  $w->pack(-side => 'top', -expand => 1, 
           -fill => "x" );
}

$entry->bind("<Return>", \&scan_done);

my $session = POE::Session->create(
  inline_states => { 
    _start => sub{
      $poe_kernel->delay("_start", 60);
  } 
});

POE::Kernel->run();

###########################################
sub scan_done {
###########################################
  $PHOTO->blank();
  $PRODUCT->configure(-text => "");
  $FOOTER->configure(-text => 
                     "Processing ...");
  $BYWHO->configure(-text => "");
  $UPC->configure(-text => $UPC_VAR);
  resp_process(
          amzn_fetch( $UPC_VAR ) );
  $UPC_VAR = "";
}

###########################################
sub amzn_fetch {
###########################################
  my($upc_or_ean) = @_;

  my $resp;

  ## tp>>
  my $amz_locale = 'us'; # default is US
  if ( length ("" . $upc_or_ean ) > 12) {
    $amz_locale = 'uk';
    print STDERR "*** $upc_or_ean looks like EAN code\n";
  } else {
    $amz_locale = 'us';
    print STDERR "*** $upc_or_ean looks like UPC code\n";
  }

  ## <<tp

  my $amzn = Net::Amazon->new(
      token => $amz_token,
      secret_key => $amz_secret,
      locale => $amz_locale, ## >>tp<<
      ua    => $UA,
  );

  #for my $current_amz_cat (@MODES) {
  # powyższe nie działa

    #my $req = Net::Amazon::Request::UPC->new(
    #              upc  => $upc, mode => $mode, );

    ## tp>> zmieniono powyższe na
    my $req ;
    if ( $amz_locale eq 'uk') {
      print STDERR "*** Fetching from $amz_locale with mode $current_amz_cat ***\n";
      $req = Net::Amazon::Request::EAN->new(
          ean  => $upc_or_ean,
          mode => $current_amz_cat,
         );
    } else {
      print STDERR "*** Fetching from $amz_locale with mode $current_amz_cat ***\n";
       $req = Net::Amazon::Request::UPC->new(
	  upc  => $upc_or_ean,
          mode => $current_amz_cat,
       );
    }

    $resp = $amzn->request($req);

    if($resp->is_success()) {
      print STDERR "** $current_amz_cat, $upc_or_ean **\n";
      return($resp, $current_amz_cat, $upc_or_ean);
      last;
    }

    WARN "Nothing found in mode '$current_amz_cat'";

  ##} ## // for teraz niepotrzebne

  return $resp;
}

###########################################
sub resp_process {
###########################################
  my($resp, $mode, $upc_or_ean) = @_;

  if($resp->is_error()) {
    $PRODUCT->configure(
                 -text => "NOT FOUND");
    return 0;
  }

  my ($property) = $resp->properties();
  my $imgurl = $property->ImageUrlMedium();

  ## zabezpieczenie jezeli ksiazka nie ma obrazka okladki (stare nie maja)

  if ($imgurl) { img_display( $imgurl ); }

  my $a = Work->new(); ### works is table name

  $a->upc($upc_or_ean); ## <--
  $a->type($mode);
  $a->title( $property->Title() );

  # eval { $answer = $a / $b; }; warn $@ if $@;
  print STDERR "***", $property->Title() , "\n";

  ## >>tp (b. szczegolowy opis, jak pole description)
  my $xml_description = "<description type='$mode' code='$upc_or_ean'>";
  ## <<tp

  if($mode eq "books") {
    ## tp>>
    eval { $resp->properties()->isbn(); } ; 
    if ($@) {## it is not a book
      print STDERR "*** ERROR: $@\n";
      $PRODUCT->configure( -text => "NOT BOOKS TYPE ITEM / REENTER"); return 1;  }
    ##<<tp

    $a->bywho( $property->author() );
    ## tp>>
    $xml_description .= "<creator>" . xml_safe($resp->properties()->author()) . "</creator>";

    $xml_description .= "<creators>";
    foreach my $a__ ( $resp->properties()->authors() ) { $xml_description .= "<c>" . xml_safe($a__) . "</c>"; }
    $xml_description .= "</creators>";

    $xml_description .= "<title>" . xml_safe($resp->properties()->title()) . "</title>";
    $xml_description .= "<publisher>" . xml_safe($resp->properties()->publisher()) . "</publisher>";
    $xml_description .= "<edition>" . xml_safe($resp->properties()->edition()) . "</edition>";
    $xml_description .= "<published>" . $resp->properties()->publication_date() . "</published>";
    $xml_description .= "<isbn>" . $resp->properties()->isbn() . "</isbn>";
    ## <<tp
  } elsif( $mode eq "music") {
    ## tp>>
    eval { $resp->properties()->media(); } ;
    if ($@) {## it is not a music item (CD)
      print STDERR "*** ERROR: $@\n";
      $PRODUCT->configure( -text => "NOT MUSIC TYPE ITEM / REENTER"); return 1;  }
    ##<<tp

    $a->bywho( $property->artist() );
    ## tp>>
    $xml_description .= "<creator>" . xml_safe($resp->properties()->artist()) . "</creator>";
    $xml_description .= "<creators>";
    foreach my $a__ ( $resp->properties()->artists() ) { $xml_description .=  "<c>" . xml_safe($a__) . "</c>"; }
    $xml_description .= "</creators>";
    $xml_description .= "<title>" . xml_safe($resp->properties()->title()) . "</title>";
    $xml_description .= "<album>" . xml_safe($resp->properties()->album()) . "</album>";

    $xml_description .= "<tracks>";
    foreach my $t__ ( $resp->properties()->tracks() ) { $xml_description .= "<t>" . xml_safe($t__) . "</t>"; }
    $xml_description .= "</tracks>";

    $xml_description .= "<label>" . xml_safe($resp->properties()->label()) . "</label>";
    $xml_description .= "<media>" . $resp->properties()->media() . "</media>";
    ## <<tp
  } else {
    $a->bywho( "" );
  }

  $xml_description .= "</description>";

  $a->description( $xml_description );

  $BYWHO->configure(-text => $a->bywho() );
  $PRODUCT->configure( 
                    -text => $a->title() );

  if($a->load( speculative => 1 )) {
      $PRODUCT->configure(
                -text => "ALREADY EXISTS");
  } else {
    $a->save();
  }

  $FOOTER->configure(
                -text => "Scan next item");
  return 1;
}

###########################################
sub img_display {
###########################################
  my($imgurl) = @_;

  my $imgresp = $UA->get( $imgurl );

  if($imgresp->is_success()) {
    $PHOTO->configure( -data => 
     encode_base64( $imgresp->content() ));
  }
}

###########################################
sub xml_safe {# remove forbidden characters
###########################################
  my($string) = @_;
  $string =~ s/\&/\&amp;/g;
  $string =~ s/\</\&lt;/g;
  return $string;
}

##
