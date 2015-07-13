#!/usr/bin/perl

# Flushing to STDOUT after each write
$| = 1; 

use strict;
use warnings;
use LWP::Simple;
use Getopt::Std;
use vars qw/ %opt /;

sub init()
{
    my $opt_string = 'i:t:h:j:c';
    getopts( "$opt_string", \%opt ) or usage();
    usage() if defined $opt{h};

    my $INDEX;
    my $url;
    my $TEMPLATE;

    if ( scalar keys(%opt) > 0 ) {

        if($opt{i}) {
                $INDEX = $opt{i};
        }
        if($opt{t}) {
                $url = "http://".$opt{t}.":9200";
        }
        if($opt{c}) {
                
            usage() if not defined $opt{i};
            
            if($opt{j}) {
                $TEMPLATE = $opt{j};
            } 

            my $templatedata;
            open TEMPLATE , "<",  $TEMPLATE or die $?;
            while (<TEMPLATE>) {

                $_ =~ s/INDEXTEMPLATE/$INDEX/;

                $templatedata = $templatedata . $_;

            }
            close TEMPLATE; 

            &createindex($url, $INDEX, $templatedata);
            &put($url, $INDEX, undef, 1, 1, 5, 0);
        }

    } else {
        usage();
    }
}

sub createindex($$$)
{
    my $url = shift;
    my $INDEX = shift;
    my $templatedata = shift;
    
    &put($url, $INDEX, $templatedata, 1, 1, 5, 1);
}

sub usage() {
        print STDERR << "EOF";

            Create indexes in Elasticsearch

            usage: $0 [-i indexname] [-t target] [-c] [-j template] 

             -h        : this (help) message
             -i        : give index name
             -t        : give target for _bulk import
             -j        : use template for index (can only be used togehter with -c)
             -c        : will create the given index ( has to be used with -i )

            example: $0 -i \$(date date "+nginx-%Y-%m-%d") -t elasticsearch.example.com

EOF
exit;

}

sub put () {
    my ($url, $INDEX, $templatedata, $METHOD, $REPLICA, $REFRESH, $CREATETEMPL) = @_;

    my $ua;
    # Sending the line to Elastic 
    $ua  = LWP::UserAgent->new();
    $ua->default_headers;

    my $http_call;
    my $postdata;
    my $activate;
    if ($METHOD eq 0) {
        $http_call = $url."/".$INDEX;
        $postdata = $templatedata;
    } elsif ($METHOD eq 1) {
        $http_call = $url."/".$INDEX."/_settings";
        $postdata = '{  "index" : { "refresh_interval" : "'.$REFRESH.'s",  "number_of_replicas" : '.$REPLICA.' }}';  
        $activate = 1;
    }
    if ($CREATETEMPL eq 1) {
        $http_call = $url."/_template/".$INDEX;
        my $response = $ua->put( $http_call, Content_Type => 'json' , Content => $templatedata )->decoded_content."\n";

        $CREATETEMPL = 0;

        $http_call = $url."/".$INDEX;
    }
    my $response = $ua->put( $http_call, Content_Type => 'json' , Content => $postdata)->decoded_content."\n";
    print $response . "\n";
    $postdata = "";
}

init();

