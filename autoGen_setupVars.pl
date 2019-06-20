#!/usr/bin/perl -w

use strict;
use DBI();

my $DATABASE_NAME = "hda_production";
my $DATABASE_USER = "amahihda";
my $DATABASE_PASSWORD = "AmahiHDARulez";

my $file_setupVars = "setupVars.conf";

my $device = `ip route | awk '/^default/ { printf \$5 }'`;

my $dbh;
my %settings;

sub mv {
	my $from = shift;
	my $to = shift;
	system ("mv " . $from . " " . $to . "/");
}

sub check_db_sanity {

	return 0 unless $dbh;

	my $sth = $dbh->prepare("SELECT value FROM settings WHERE name = 'api-key'");
	$sth->execute();

	my @row = ();
	@row = $sth->fetchrow_array;
	my $value = $row[0];
	$sth->finish();

	return 1 if (length($value) == 40);
	return 0;
}

sub db_connect {

	# wait forever until the DB is up
	while (1) {
                $dbh = DBI->connect("DBI:mysql:database=$DATABASE_NAME;host=localhost",
                                $DATABASE_USER, $DATABASE_PASSWORD);
		if ($dbh && &check_db_sanity()) {
			return;
		}
		sleep(60);
	}
}

sub get_db_settings {

	my $sth = $dbh->prepare("SELECT name, value FROM settings");
	$sth->execute();

	my @row = ();
	while (@row = $sth->fetchrow_array) {
		my $name = $row[0];
		my $value = $row[1];
		$settings {$name} = $value;
	}
	$sth->finish();
}

sub netmask_to_prefix () {
    my $pp = "255.255.255.0";
    my $prefix_cidr = `ipcalc -p 1.1.1.1 $pp`;
    $prefix_cidr =~ s/\D//g;
    return ($prefix_cidr);
}

sub resolve_dns_ips {
	unless (defined($settings{'dns'})) {
		# big ol' default for dns
		return ("1.1.1.1", "1.0.0.1");
	}
	my $service = $settings{'dns'};
	if ($settings{'dns'} eq 'opendns') {
		return ("208.67.222.222", "208.67.220.220");
	}
	if ($settings{'dns'} eq 'google') {
		return ("8.8.8.8", "8.8.4.4");
	}
	if ($settings{'dns'} eq 'cloudflare') {
		return ("1.1.1.1", "1.0.0.1");
	}
	my $extdns1 = "8.8.8.8"; # 2nd default
	my $extdns2 = "8.8.4.4"; # 2nd default
	$extdns1 = $settings{'dns_ip_1'} if (defined($settings{'dns_ip_1'}));
	$extdns2 = $settings{'dns_ip_2'} if (defined($settings{'dns_ip_2'}));
	return ($extdns1, $extdns2);
}

sub print_setupVars {
    my $domain = $settings{'domain'};
	my $net = $settings{'net'};
	my $netmask_size = $settings{'netmask_size'};
	my $gw = $net . "." . $settings{'gateway'};
	my $self = $net . "." . $settings{'self-address'};
	my $dns1 = $self;
	my ($extdns1, $extdns2) = &resolve_dns_ips();
    my $prefix = &netmask_to_prefix($netmask_size);
	open(my $generate_settings, ">", $file_setupVars);
	printf $generate_settings "PIHOLE_INTERFACE=$device\n";
	printf $generate_settings "IPV4_ADDRESS=$self/$prefix\n";
    printf $generate_settings "IPV6_ADDRESS=\n";
    printf $generate_settings "PIHOLE_DNS_1=$extdns1\n";
    printf $generate_settings "PIHOLE_DNS_2=$extdns2\n";
    printf $generate_settings "QUERY_LOGGING=true\n";
    printf $generate_settings "INSTALL_WEB_SERVER=false\n";
    printf $generate_settings "INSTALL_WEB_INTERFACE=true\n";
    printf $generate_settings "LIGHTTPD_ENABLED=false\n";
    printf $generate_settings "BLOCKING_ENABLED=true\n";
    printf $generate_settings "WEBPASSWORD=4842d773f9430b61ee2994ccde8ca60b1a4495c941594c242aeeb3767daca3d4\n";
	close $generate_settings;

	&mv ($file_setupVars, "/etc/pihole/");
}

sub main {
	&db_connect ();
    &get_db_settings ();
    &print_setupVars ();      
	# exit normally
	exit 0;
}

&main ();