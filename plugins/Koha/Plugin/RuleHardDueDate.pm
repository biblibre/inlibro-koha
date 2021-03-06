package Koha::Plugin::RuleHardDueDate;

# Bouzid Fergani, 2016 - InLibro
#
# This plugin allow you to modify hard due date for selected branch and you can cancel it.
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under th
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use Modern::Perl;

use base qw(Koha::Plugins::Base);

use CGI;
use C4::Context;
use Koha::DateUtils;
use C4::Members;
use C4::Koha;

our $VERSION = 1.3;

our $metadata = {
    name   => 'Rules hard due dates',
    author => 'Bouzid Fergani',
    description => 'Rules hard due dates',
    date_authored   => '2016-12-20',
    date_updated    => '2017-08-08',
    minimum_version => '16.05',
    maximum_version => undef,
    version         => $VERSION,
};
my $new_version =0;
eval("use Koha::ItemTypes");
eval("use Koha::Patron::Categories");
if(!$@){
    $new_version =1;
}

sub new {
    my ( $class, $args ) = @_;
    $args->{'metadata'} = $metadata;
    my $self = $class->SUPER::new($args);
    return $self;
}

sub tool {
     my ( $self, $args ) = @_;
     my $cgi = $self->{'cgi'};
     my $op = $cgi->param('op');
     my $branchcode = $cgi->param('branch');
     my $harduedate = $cgi->param('duedate');
     my $addcancel = $cgi->param('addcancel');
     my $category = $cgi->param('category');
     my $itemtype = $cgi->param('itemtype');
     if ($op && $op eq 'valide'){
         my $preferedLanguage = $cgi->cookie('KohaOpacLanguage');
         my $template = undef;
         eval {$template = $self->get_template( { file => "rule_hard_due_date_$preferedLanguage.tt" }  )};
         if(!$template){
             $preferedLanguage = substr $preferedLanguage, 0, 2;
             eval {$template = $self->get_template( { file => "messaging_preference_wizard_$preferedLanguage.   tt" } )};
         }
         $template = $self->get_template( { file => 'rule_hard_due_date.tt' } ) unless $template;
         my $branchloop = &GetBranchs();
        my $categorieloop;
        if($new_version) {
            $categorieloop = Koha::Patron::Categories->search();
        }else{
            $categorieloop = &GetBorrowercategoryList();
        }
         &UpdateHardDueDate($branchcode,$harduedate,$addcancel,$category,$itemtype);
         $template->param(
             branchloop => $branchloop,
             categorieloop => $categorieloop,
             confirmation => 1,
         );
         print $cgi->header(-type => 'text/html',-charset => 'utf-8');
         print $template->output();
     }else{
         $self->show_config_pages();
     }
 }

 sub show_config_pages {
     my ( $self, $args) = @_;
     my $cgi = $self->{'cgi'};
     my $preferedLanguage = $cgi->cookie('KohaOpacLanguage');
     my $template = undef;
     eval {$template = $self->get_template( { file => "rule_hard_due_date_$preferedLanguage.tt" } )};
     if(!$template){
         $preferedLanguage = substr $preferedLanguage, 0, 2;
         eval {$template = $self->get_template( { file => "rule_hard_due_date_$preferedLanguage.tt" } )};
     }
     $template = $self->get_template( { file => 'rule_hard_due_date.tt' } ) unless $template;
     my $branchloop = &GetBranchs();
     my $categorieloop;
     if($new_version) {
         $categorieloop = Koha::Patron::Categories->search;
     }else{
         $categorieloop = &GetBorrowercategoryList();
     }
     my $itemtypeloop = &GetItemsTypes();
     $template->param(
         branchloop => $branchloop,
         categorieloop => $categorieloop,
         itemtypeloop => $itemtypeloop,
         confirmation  => 0,
     );
     print $cgi->header(-type => 'text/html',-charset => 'utf-8');
     print $template->output();
 }

 sub UpdateHardDueDate {
     my ($branchcode, $hardduedate, $addcancel, $category, $itemtype) = @_;
     my $dbh   = C4::Context->dbh;
     my $issues_affected = 0;
     my $hard_due_date = ($addcancel eq 'add') ? $hardduedate : undef;
     my $sql = qq{
         UPDATE issuingrules
         SET hardduedate = ?, hardduedatecompare = ?
     };
     my $where;
     my $wherebranch = ($branchcode eq "all") ? "" : " branchcode = '$branchcode'";
     $where = " WHERE $wherebranch" if $wherebranch;
     my $whereCat = ($category eq "all") ? "" : " categorycode = '$category'";
     #$wheres = ($where) ? $where : "";
     if ($where) {
         $where = ($whereCat) ? $where ." AND " . $whereCat : $where;
     }else{
         $where = ($whereCat) ? " WHERE $whereCat " : ''
     }
     my $whereItType =  ($itemtype eq "all") ? "" : " itemtype = '$itemtype'";
     if ($where){
         $where = ($whereItType) ? $where . " AND " . $whereItType : $where;
     }else{
         $where = ($whereItType) ? " WHERE $whereItType " : '';
     }
     $sql .= $where if ($where);
     my $sth = $dbh->prepare($sql);
     $sth->execute($hard_due_date,-1);
 }

sub GetBranchs {
    my $branches = { map { $_->branchcode => $_->unblessed } Koha::Libraries->search };
    my $branchloop;
    for my $thisbranch (sort { $branches->{$a}->{branchname} cmp $branches->{$b}->{branchname} } keys %{$branches}) {
        push @{$branchloop}, {
            value => $thisbranch,
            branchname => $branches->{$thisbranch}->{'branchname'},
        };
    }
    return $branchloop;
}

sub GetItemsTypes {
    my $itemtypes;
    if ($new_version){
        $itemtypes = { map { $_->itemtype => $_->unblessed } Koha::ItemTypes->search };
    } else{
        $itemtypes = GetItemTypes();
    }

    my @itemtypesloop;
    foreach my $thisitemtype ( sort keys %$itemtypes ) {
        my %row = (
            value       => $thisitemtype,
            description => $itemtypes->{$thisitemtype}->{description},
        );
        push @itemtypesloop, \%row;
    }
    return \@itemtypesloop
}

sub uninstall() {
     my ( $self, $args ) = @_;
     my $table = $self->get_qualified_table_name('mytable');

     return C4::Context->dbh->do("DROP TABLE $table");
 }

1;
