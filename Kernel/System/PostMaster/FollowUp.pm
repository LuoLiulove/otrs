# --
# PostMaster.pm - the global PostMaster module for OpenTRS
# Copyright (C) 2001 Martin Edenhofer <martin+code@otrs.org>
# --
# $Id: FollowUp.pm,v 1.1 2001-12-26 20:06:25 martin Exp $
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see 
# the enclosed file COPYING for license information (GPL). If you 
# did not receive this file, see http://www.gnu.org/licenses/gpl.txt.
# --

package Kernel::System::PostMaster::FollowUp;

use strict;
use Kernel::System::PostMaster::AutoResponse;

use vars qw($VERSION);
$VERSION = '$Revision: 1.1 $';
$VERSION =~ s/^.*:\s(\d+\.\d+)\s.*$/$1/;

# --
sub new {
    my $Type = shift;
    my %Param = @_;

    my $Self = {}; # allocate new hash for object
    bless ($Self, $Type);

    $Self->{Debug} = 0;

    foreach (keys %Param) {
        $Self->{$_} = $Param{$_};
    }

    # check needed Opjects
    foreach ('DBObject', 'TicketObject', 'ArticleObject', 'LogObject') {
        die "Got no $_!" if (!$Self->{$_});
    }

    return $Self;
}
# --
sub Run {
    my $Self = shift;
    my %Param = @_;
    my $TicketID = $Param{TicketID};
    my $InmailUserID = $Param{InmailUserID}; 
    my $GetParamTmp = $Param{GetParam};
    my %GetParam = %$GetParamTmp;
    my $Tn = $Param{Tn};
    my $Email = $Param{Email};
    my $State = $Param{State} || '';
	my $Comment = $Param{Comment} || '';
    my $Lock = $Param{Lock} || '';
    my $QueueID = $Param{QueueID};
    my $AutoResponseType = $Param{AutoResponseType} || '';

    my $DBObject = $Self->{DBObject};
    my $ArticleObject = $Self->{ArticleObject};
    my $TicketObject = $Self->{TicketObject};
    my $LogObject = $Self->{LogObject};

    my $OldState = $TicketObject->GetState(TicketID => $TicketID) || '';

    # do db insert
    my $ArticleID = $ArticleObject->CreateArticleDB(
        TicketID => $TicketID,
        ArticleType => 'email',
        SenderType => 'customer',
        From => $GetParam{From},
        ReplyTo => $GetParam{ReplyTo},
        To => $GetParam{To},
        Cc => $GetParam{Cc},
        Subject => $GetParam{Subject},
        MessageID => $GetParam{'Message-ID'},
        Body => $GetParam{Body},
        CreateUserID => $InmailUserID,
    );

    # write to fs
    $ArticleObject->WriteArticle(ArticleID => $ArticleID, Email => $Email);

    # set free article text
    my @Values = ('X-OTRS-ArticleKey', 'X-OTRS-ArticleValue');
    my $CounterTmp = 0;
    while ($CounterTmp <= 3) {
        $CounterTmp++;
        if ($GetParam{"$Values[0]$CounterTmp"} && $GetParam{"$Values[1]$CounterTmp"}) {
            $ArticleObject->SetFreeText(
                ArticleID => $ArticleID,
                Key => $GetParam{"$Values[0]$CounterTmp"},
                Value => $GetParam{"$Values[1]$CounterTmp"},
                Counter => $CounterTmp,
                UserID => $InmailUserID,
            );
        }
    }
    # set state 
    if ($State && ($OldState ne $State)) {
	    $TicketObject->SetState(
    	    State => $State,
        	TicketID => $TicketID,
	        UserID => $InmailUserID,
    	);
    }
    # add history row
    $TicketObject->AddHistoryRow(
        TicketID => $TicketID,
        HistoryType => 'FollowUp',
        ArticleID => $ArticleID,
        Name => "FollowUp for [$Tn]. $Comment",
        CreateUserID => $InmailUserID,
    );
   
    if ($Lock && !$TicketObject->GetLockState(TicketID => $TicketID) && $OldState =~ /^close/i) {
       $TicketObject->SetLock( 
           TicketID => $TicketID,
           Lock => 'lock',
           UserID => => $InmailUserID,
       );
    }

    # write log
    $LogObject->Log(
        MSG => "FollowUp Article to Ticket [$Tn] created (TicketID=$TicketID, " .
			"ArticleID=$ArticleID). $Comment"
    );

    # --
    # send auto response?
    my $AutoResponse = Kernel::System::PostMaster::AutoResponse->new(
        DBObject => $DBObject,
    );
    my %Data = $AutoResponse->GetResponseData(
        OueueID => $QueueID,
        Type => $AutoResponseType,
    );
    if ($Data{Text} && $Data{Realname} && $Data{Address} && !$GetParam{'X-OTRS-Loop'}) {
        # do article db insert
        my $ArticleID = $ArticleObject->CreateArticleDB(
            TicketID => $TicketID,
            ArticleType => 'email',
            SenderType => 'system',
            From => "$Data{Realname} <$Data{Address}>",
            To => $GetParam{From},
            Subject => "[Ticket#$Tn] $Data{Subject}",
            MessageID => time() .".". rand(999999),
            Body => $Data{Text},
            CreateUserID => $InmailUserID,
        );
        my $Email = Kernel::System::Email->new();
        $Email->SendMail(
            DBObject => $DBObject,
            From => "$Data{Realname} <$Data{Address}>",
            Email => $Data{Address},
            To => $GetParam{From},
            RealName => $Data{Realname},
            Subject => "[Ticket#$Tn] $Data{Subject}",
            UserID => $InmailUserID,
            TicketID => $TicketID,
            TicketObject => $TicketObject,
            ArticleID => $ArticleID,
            Body => $Data{Text},
            InReplyTo => $GetParam{'Message-ID'},
            Loop => 1,
            HistoryType => 'SendAutoFollowUp',
        );

        # do log
        $LogObject->Log(MSG => "Sent auto follow up for Ticket [$Tn] (TicketID=$TicketID, " .
            "ArticleID=$ArticleID) to '$GetParam{From}' "
        );

    }
    else {
        # do log
        $LogObject->Log(MSG => "Sent no auto follow up for Ticket [$Tn] " .
			"($GetParam{From})."
       );
    }

    if ($Self->{Debug} > 0) {
       $LogObject->Log(
            MSG => "Debug($Self->{Debug}): AutoResponseType=$AutoResponseType, " .
			"ResponseFrom=$Data{Address}, QueueID=$QueueID, " .
            "Mailing-List=$GetParam{'Mailing-List'}, " .
            "Precedence=$GetParam{Precedence}, X-Loop=$GetParam{'X-Loop'}, " .
            "X-No-Loop=$GetParam{'X-No-Loop'}, X-OTRS-Loop=$GetParam{'X-OTRS-Loop'}."
        );

    }

    return 1;
}
# --

1;
