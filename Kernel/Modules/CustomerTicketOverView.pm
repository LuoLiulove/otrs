# --   
# Kernel/Modules/CustomerTicketOverView.pm - status for all open tickets
# Copyright (C) 2001-2004 Martin Edenhofer <martin+code at otrs.org>
# --   
# $Id: CustomerTicketOverView.pm,v 1.26 2004-06-22 11:44:39 martin Exp $
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see http://www.gnu.org/licenses/gpl.txt.
# --

package Kernel::Modules::CustomerTicketOverView;

use strict;
use Kernel::System::State;

use vars qw($VERSION);
$VERSION = '$Revision: 1.26 $';
$VERSION =~ s/^\$.*:\W(.*)\W.+?$/$1/;

# --
sub new {
    my $Type = shift;
    my %Param = @_;
    # allocate new hash for object
    my $Self = {};
    bless ($Self, $Type);
    # get common opjects
    foreach (keys %Param) {
        $Self->{$_} = $Param{$_};   
    }
    # check all needed objects
    foreach (qw(ParamObject DBObject LayoutObject ConfigObject LogObject UserObject)) {
        die "Got no $_" if (!$Self->{$_});
    }
    # state object
    $Self->{StateObject} = Kernel::System::State->new(%Param);

    # all static variables
    $Self->{ViewableSenderTypes} = $Self->{ConfigObject}->Get('ViewableSenderTypes')
          || die 'No Config entry "ViewableSenderTypes"!';
    # get params 
    $Self->{ShowClosedTickets} = $Self->{ParamObject}->GetParam(Param => 'ShowClosedTickets');
    $Self->{SortBy} = $Self->{ParamObject}->GetParam(Param => 'SortBy') || 'Age';
    $Self->{Order} = $Self->{ParamObject}->GetParam(Param => 'Order') || 'Up';
    $Self->{StartHit} = $Self->{ParamObject}->GetParam(Param => 'StartHit') || 1; 
    $Self->{Type} = $Self->{ParamObject}->GetParam(Param => 'Type') || 'MyTickets'; 
    if ($Self->{StartHit} >= 1000) {
        $Self->{StartHit} = 1000;
    }
    $Self->{PageShown} = $Self->{UserShowTickets} || $Self->{ConfigObject}->Get('CustomerPreferencesGroups')->{ShownTickets}->{DataSelected} || 1;  
 
    return $Self;
}
# --
sub Run {
    my $Self = shift;
    my %Param = @_;
    # store last screen
    if (!$Self->{SessionObject}->UpdateSessionID(
        SessionID => $Self->{SessionID},
        Key => 'LastScreen',
        Value => $Self->{RequestedURL},
    )) {
        my $Output = $Self->{LayoutObject}->CustomerHeader(Title => 'Error');
        $Output .= $Self->{LayoutObject}->CustomerError();
        $Output .= $Self->{LayoutObject}->CustomerFooter();
        return $Output;
    }
    # check needed CustomerID
    if (!$Self->{UserCustomerID}) {
        my $Output = $Self->{LayoutObject}->CustomerHeader(Title => 'Error');
        $Output .= $Self->{LayoutObject}->CustomerError(Message => 'Need CustomerID!!!');
        $Output .= $Self->{LayoutObject}->CustomerFooter();
        return $Output;
    }
    # starting with page ...
    my $Refresh = '';
    if ($Self->{UserRefreshTime}) {
        $Refresh = 60 * $Self->{UserRefreshTime};
    }
    my $Output = $Self->{LayoutObject}->CustomerHeader(
        Title => $Self->{Type},
        Refresh => $Refresh,
    );
    # build NavigationBar
    $Output .= $Self->{LayoutObject}->CustomerNavigationBar();
    # to get the output faster!
    print $Output; $Output = '';
    # check if just open tickets should be shown
    my $SQLExt = '';
    my $ShowClosed = 0;
    if (!defined($Self->{ShowClosedTickets})) {
        if (defined($Self->{UserShowClosedTickets})) {
            $ShowClosed = $Self->{UserShowClosedTickets};
        }
        else {
            $ShowClosed = $Self->{ConfigObject}->Get('CustomerPreferencesGroups')->{ClosedTickets}->{DataSelected};
        }
    }
    else {
        $ShowClosed = $Self->{ShowClosedTickets};
    }
    # get data (viewable tickets...)
    my $StateType = '';
    if (!$ShowClosed) {
       $StateType = 'Open';
    }

    my @ViewableTickets = ();
    if ($Self->{Type} eq 'MyTickets') {
        @ViewableTickets = $Self->{TicketObject}->TicketSearch(
            Result => 'ARRAY',
            CustomerUserLogin => $Self->{UserID}, 
            StateType => $StateType,
            OrderBy => $Self->{Order},
            SortBy => $Self->{SortBy},

            CustomerUserID => $Self->{UserID},
            Permission => 'ro',
        );
    }
    else {
        @ViewableTickets = $Self->{TicketObject}->TicketSearch(
            Result => 'ARRAY',
            StateType => $StateType,
            OrderBy => $Self->{Order},
            SortBy => $Self->{SortBy},

            CustomerUserID => $Self->{UserID},
            Permission => 'ro',
        );
    }

    my $AllTickets = @ViewableTickets;
    # show ticket's
    my $OutputTable = "";
    my $Counter = 0;
    foreach my $TicketID (@ViewableTickets) {
      $Counter++;
      if ($Counter >= $Self->{StartHit} && $Counter < ($Self->{PageShown}+$Self->{StartHit})) {
        $OutputTable .= $Self->ShowTicketStatus(TicketID => $TicketID);
      }
    }
    # create & return output
    my %PageNav = $Self->{LayoutObject}->PageNavBar(
        Limit => 10000,
        StartHit => $Self->{StartHit},
        PageShown => $Self->{PageShown},
        AllHits => $AllTickets,
        Action => "Action=CustomerTicketOverView",
        Link => "SortBy=$Self->{SortBy}&Order=$Self->{Order}&ShowClosedTickets=$ShowClosed&Type=$Self->{Type}&",
    );
    # create & return output
    $Output .= $Self->{LayoutObject}->Output(
        TemplateFile => 'CustomerStatusView', 
        Data => {
            StatusTable => $OutputTable,
            Type => $Self->{Type},
            ShowClosed => $ShowClosed,
            %PageNav,
            %Param,
        },
    );

    # get page footer
    $Output .= $Self->{LayoutObject}->CustomerFooter();
    
    # return page
    return $Output;
}
# --
# ShowTicket
# --
sub ShowTicketStatus {
    my $Self = shift;
    my %Param = @_;
    my $TicketID = $Param{TicketID} || return;
    # get last article
    my %Article = $Self->{TicketObject}->ArticleLastCustomerArticle(TicketID => $TicketID);
    # condense down the subject
    my $TicketHook = $Self->{ConfigObject}->Get('TicketHook');
    my $Subject = $Article{Subject};
    $Subject =~ s/^RE://i;
    $Subject =~ s/\[${TicketHook}:.*\]//;
    # return ticket
    $Article{Age} = $Self->{LayoutObject}->CustomerAge(Age => $Article{Age}, Space => ' ') || 0;
    # create & return output
    return $Self->{LayoutObject}->Output(
        TemplateFile => 'CustomerStatusViewTable', 
        Data => {
            %Article,
            Subject => $Subject,
            %Param,
        },
    );
}
# --

1;
