unit frmmain;
{ Copyright (c) 2018 by Preben Björn Biermann Madsen
  email: prebenbjornmadsen@gmail.com
  http://pascalcoin.frizen.eu

  Distributed under the MIT software license, see the accompanying file LICENSE
  or visit http://www.opensource.org/licenses/mit-license.php.

  This is a part of the Pascal Coin Project.

  If you like it, consider a donation using Pascal Coin Account: 274800-71
}
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ComCtrls, ExtCtrls, Menus, StrUtils, httpsend, janSQL;

type

  { TFormMain }

  TFormMain = class(TForm)
    btStart: TButton;
    cbTime: TComboBox;
    edAccount: TEdit;
    edIP: TEdit;
    edPort: TEdit;
    Image1: TImage;
    Label1: TLabel;
    Label2: TLabel;
    lbInterval: TLabel;
    lbAccount: TLabel;
    MainMenu1: TMainMenu;
    mmDisplay: TMemo;
    mmLog: TMemo;
    Panel1: TPanel;
    Panel2: TPanel;
    Panel3: TPanel;
    StatusBar1: TStatusBar;
    btRefresh: TButton;
    Timer1: TTimer;
    procedure btStartClick(Sender: TObject);
    procedure btRefreshClick(Sender: TObject);
    procedure FormActivate(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
  private
    { private declarations }
    FSelectedAccount: string;
    FList: TStringList;
    FSeenBlk : integer;

    appdir:string;
    db:TjanSQL;
    function String2Hex(const Buffer: ansistring): string;
    function Hex2Str(const Buffer: ansistring): string;
    function SendRequest(method, params: string): String;
    procedure ReadIni();
    procedure WriteIni();
    procedure Display(buf: ansistring);
    procedure Log(buf: ansistring);
    procedure GetAccountOperations();
    procedure Tokenize(var str, tx, pay, oph: string);
    procedure DoSql(query: string);
    procedure Process_Return(oph, pay: string);
    procedure Process_Forward(oph, pay: string);
    procedure Process_Lock(oph, pay: string);
    procedure Process_Escrow(oph, txt, pay: string);
    procedure Process_Error(oph, pay: string);
  public
    { public declarations }
  end;

var
  FormMain: TFormMain;

implementation

{$R *.lfm}

{$IFDEF UNIX}
const eol = #10;
{$ELSE}
const eol = #13#10;
{$ENDIF}
const
  IniFile = 'escrow.ini';

{ TFormMain }
procedure TFormMain.ReadIni();
var
  f: TextFile;
  s: string;
begin
 AssignFile(f, IniFile);
 try
   reset(f);
   readln(f, s);
   edIP.Text := s;
   readln(f, s);
   edPort.Text := s;
   readln(f, s);
   edAccount.Text := s;
   FSelectedAccount := s;
   readln(f, s);
   cbTime.Text := s;
   readln(f, s);
   FSeenBlk := StrToInt(s);
   CloseFile(f);
 except
   on E: EInOutError do
    ShowMessage('File handling error occurred.');
 end;
end;

procedure TFormMain.WriteIni();
var
  f: TextFile;
  s: string;
  i: integer;
begin
  AssignFile(f, IniFile);
  try
    rewrite(f);
    s := trim(edIP.Text);
    writeln(f, s);
    s := trim(edPort.Text);
    writeln(f, s);
    i := pos('-', edAccount.Text);
    if i > 0 then s := trim(copy(edAccount.Text, 1, i - 1))
    else s := trim(edAccount.Text);
    writeln(f, s);
    s := trim(cbTime.Text);
    writeln(f, s);
    writeln(f, IntToStr(FSeenBlk));
    CloseFile(f);
  except
    on E: EInOutError do
     ShowMessage('File handling error occurred.');
  end;
end;

function TFormMain.String2Hex(const Buffer: Ansistring): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(Buffer) do
  Result := UpperCase(Result + IntToHex(Ord(Buffer[i]), 2));
end;

Function TFormMain.Hex2Str(const Buffer: Ansistring): String;
var i: Integer;
begin
  Result:=''; i:=1;
  While i<Length(Buffer) Do Begin
    Result:=Result+Chr(StrToIntDef('$'+Copy(Buffer,i,2),0));
    Inc(i,2);
  End;
end;

procedure TFormMain.Display(buf: ansistring);
begin
  mmDisplay.Lines.Add(buf);
  mmDisplay.SelStart := Length(mmDisplay.Text);
end;

procedure TFormMain.Log(buf: ansistring);
begin
  mmLog.Lines.Add(buf);
  mmLog.SelStart := Length(mmLog.Text);
end;

function TFormMain.SendRequest(method, params: string): String;
var
    response: TMemoryStream;
    request, str, url: string;
begin
    request := '{"jsonrpc":"2.0","method":"' + method + '","params":{' + params + '},"id":123}';
    str := '';
    result := '';
    url := 'http://' + trim(edIP.Text) + ':' + trim(edPort.Text);
    response := TMemoryStream.Create;
    try
      if HttpPostURL(url, request, response) then
      begin
           SetLength(str, response.Size);
           Move(response.memory^, str[1], response.size);
      end;
    finally
      response.Free;
    end;
    result := str;
end;

procedure TFormMain.btStartClick(Sender: TObject);
begin
  if btStart.Caption = 'Start' then
  begin
    Timer1.Interval := StrToInt(cbTime.Text) * 1000;
    Timer1.Enabled := true;
    btStart.Caption := 'Stop';
    Timer1Timer(self);
  end
  else
  begin
    Timer1.Enabled := false;
    btStart.Caption := 'Start';
  end;
end;

procedure TFormMain.btRefreshClick(Sender: TObject);
begin
  GetAccountOperations;
  Statusbar1.SimpleText := 'Last block: ' + IntToStr(FSeenBlk);
end;

procedure TFormMain.FormActivate(Sender: TObject);
var
  str: string;
begin
  str := SendRequest('nodestatus', '');
  if Pos('"ready":true', str) < 1 then
  begin
    showmessage('No Connection - Check if your wallet is running and allow connections');
  end;
  str := 'connect to '''+appdir+PathDelim+'db''';
  DoSql(str);
  Log(str);
end;

procedure TFormMain.FormCreate(Sender: TObject);
begin
  FSelectedAccount := '';
  FSeenBlk := 0;
  ReadIni();
  appdir:=extractfiledir(application.exename);
  db := TjanSQL.Create;
  FList := TStringList.Create;
end;

procedure TFormMain.FormDestroy(Sender: TObject);
begin
  WriteIni();
  FreeAndNil(db);
  FreeAndNil(FList);
end;

procedure TFormMain.DoSql(query: string);
var
  sqlresult: integer;
  str: string;
  i, j, rc, fc: integer;
begin
  FList.Clear;
  str := query;
  sqlresult:=db.SQLDirect(str);

  if sqlresult <> 0 then
  begin
    if sqlresult > 0 then
    begin
      rc :=db.RecordSets[sqlresult].recordcount;
      if rc=0 then exit;
      fc:=db.RecordSets[sqlresult].fieldcount;
      if fc=0 then exit;

      for i:=0 to rc-1 do
       for j := 0 to  fc-1 do
         FList.Add(db.RecordSets[sqlresult].records[i].fields[j].value);

      if not db.RecordSets[sqlresult].intermediate then
         db.ReleaseRecordset(sqlresult);
    end;
  end
  else
    Log('DoSql Error: ' + db.Error);
end;

procedure TFormMain.Process_Return(oph, pay: string);
var
  i, j: integer;
  str, id, send, params: string;
  f: single;
begin
  i := pos(' ', pay);
  if ((i > 6) and (i < 9)) then id := Trim(Copy(pay, i+1, 24));
  send := copy(oph, 9, 8);
  DoSql('SELECT * FROM escrow_db WHERE userid='''+ id + '''');

  if (FList.Count < 5) or (send <> FList[1])  or (FList[4] <> 'waiting') then
  begin
    process_error(oph, pay);
    Log('Error - Return check doesnt match - sender: ' + IntToStr(SwapEndian(Hex2Dec(copy(oph, 9, 8)))));
    Exit;
  End;

  i := SwapEndian(Hex2Dec(copy(id, 1, 8))) + 288; // 288 blocks befoer a return request can be executed - about 24 hour;
  j := SwapEndian(Hex2Dec(copy(oph, 1, 8)));
  if (i > j) then
  begin
    process_error(oph, pay);
    Log('Error - Return request too early - sender: ' + IntToStr(SwapEndian(Hex2Dec(copy(oph, 9, 8)))));
    Exit;
  End;

  send := IntToStr(SwapEndian(Hex2Dec(copy(oph, 9, 8))));
  f := StrToFloat(FList[2]);

  params := '"sender":' + FSelectedAccount +
  ',"target":' + send +
  ',"amount":' + FormatFloat('0.####', f * 0.99) +
  ',"fee":0.0001' +
  ',"payload":"' + String2Hex('From Escrow: ' + pay) + '","payload_method":"none","pwd":""';

  str := SendRequest('sendto', params);

  DoSql('UPDATE escrow_db SET status=finish WHERE userid='''+ id + ''';COMMIT');
end;

procedure TFormMain.Process_Forward(oph, pay: string);
var
  i: integer;
  f: single;
  str, s, id, send, params: string;
begin
  i := pos(' ', pay);
  if ((i > 7) and (i < 10)) then
  begin
    id := Trim(Copy(pay, i+1, 24));
    s := Trim(Copy(pay, i+1, 64));
  end;
  send := copy(oph, 9, 8);

  DoSql('SELECT * FROM escrow_db WHERE userid=''' + id + '''');

  if ((FList.Count < 5) or (send <> FList[1]) or (FList[4] <> 'waiting')) then
  begin
    process_error(oph, pay);
    Log('Error - Forward check doesnt match - sender: ' + IntToStr(SwapEndian(Hex2Dec(copy(oph, 9, 8)))));
    Exit;
  end;

  f := StrToFloat(FList[2]);

  params := '"sender":' + FSelectedAccount +
  ',"target":' + FLIST[3] +
  ',"amount":' + FormatFloat('0.####', f * 0.99) +
  ',"fee":0.0001' +
  ',"payload":"' + String2Hex('From Escrow OpHash: ' + s) + '","payload_method":"none","pwd":""';

  str := SendRequest('sendto', params);

  DoSql('UPDATE escrow_db SET status=finish WHERE userid='''+ id + ''';COMMIT');
end;

procedure TFormMain.Process_Lock(oph, pay: string);
var
  i: integer;
  str, id, s, params, send: string;
begin
  i := pos(' ', pay);
  if ((i > 4) and (i < 7))  then
  begin
    id := Trim(Copy(pay, i+1, 24));
    s := Trim(Copy(pay, i+1, 64));
  end;

  send := IntToStr(SwapEndian(Hex2Dec(copy(oph, 9, 8))));
  DoSql('SELECT * FROM escrow_db WHERE userid='''+ id + '''');

  if (FList.Count < 5) or (send <> FList[3]) or (FList[4] <> 'waiting') then
  begin
    process_error(oph, pay);
    Log('Error - Lock check doesnt match - sender: ' + IntToStr(SwapEndian(Hex2Dec(copy(oph, 9, 8)))));
    Exit;
  end;

  params := '"sender":' + FSelectedAccount +
  ',"target":' + FList[3] +
  ',"amount":0.0001' +
  ',"fee":0.0001' +
  ',"payload":"' + String2Hex('From Escrow - We have frozen OpHash: ' + s + ' contact us email@mail.com') + '","payload_method":"none","pwd":""';

  str := SendRequest('sendto', params);

  send := IntToStr(SwapEndian(Hex2Dec(FList[1])));
  params := '"sender":' + FSelectedAccount +
  ',"target":' + send +
  ',"amount":0.0001' +
  ',"fee":0.0001' +
  ',"payload":"' + String2Hex('From Escrow - We have frozen OpHash: ' + s + ' contact us email@mail.com') + '","payload_method":"none","pwd":""';

  str := SendRequest('sendto', params);

  DoSql('UPDATE escrow_db SET status=locked WHERE userid='''+ id + ''';COMMIT');
end;

procedure TFormMain.Process_Escrow(oph, txt, pay: string);
var
  s, send, recv, amo: string;
  f: currency; //single;
  i, j, k: integer;
begin
  DoSql('SELECT * FROM escrow_db WHERE userid='''+ oph + '''');
  if (FList.Count > 0) then
  begin
    Log('Error - This operation has seen before'); //* Serious Error - should stop the program
    Exit;
  end;

  send := copy(oph, 9, 8);
  i := pos(' ', pay) + 1;
  j := pos('-', pay);
  if ((i > 1) and (j > i)) then s := copy(pay, i, j - i)
  else if (i > 1) then s := copy(pay, i, 7)
  else
  begin
    process_error(oph, pay);
    Log('Error 1 - Escrow check doesnt match - sender: ' + IntToStr(SwapEndian(Hex2Dec(copy(oph, 9, 8)))));
    exit;
  end;

  j := pos('Tx-In ', txt) + 6;
  k := pos(' PASC', txt);
  if (j > 6) and (k > j) then
  begin
    amo := copy(txt, j, k - j);
  end
  else
  begin
    process_error(oph, pay);
    Log('Error 2 - Escrow check doesnt match - sender: ' + IntToStr(SwapEndian(Hex2Dec(copy(oph, 9, 8)))));
    Exit;
  end;

  i := StrToIntDef(s, 0);
  f := StrToFloat(amo);

  if ((i = 0) or (f < 0.1)) then
  begin
    process_error(oph, pay);
    Log('Error 3 - Escrow check doesnt match - sender: ' + IntToStr(SwapEndian(Hex2Dec(copy(oph, 9, 8)))));
    Exit;
  end;

  recv := inttostr(i);

  DoSQL('INSERT INTO escrow_db (userid,sender,amount,receiver,status) VALUES ('''+oph+''','''+send+''','''+amo+''','''+recv+''',''waiting'');COMMIT');
//* could send a message to the receiver
end;

procedure TFormMain.Process_Error(oph, pay: string);
begin
  DoSQL('INSERT INTO error_db (userid,payload) VALUES ('''+oph+''','''+pay+''');COMMIT');
end;

procedure TFormMain.Tokenize(var str, tx, pay, oph: string);
var
    i, j: integer;
    s: string;
begin
  tx := ''; pay := ''; oph := '';
  i := pos('Tx-In', str);
  if i > 0 then
  begin
    s := copy(str, i, 65);
    j := pos('",', s);
    if j > 0 then tx := copy(s, 1, j)
    else Exit;
  end
  else Exit;

  i := pos('payload', str) + 10;
  if i > 11 then
  begin
    s := copy(str, i, 256);
    j := pos('"', s);
    if j > 0 then pay := trim(Hex2Str(copy(s, 1, j)))
    else Exit;
    for i := 1 to Length(pay) - 1 do
      if not (pay[i] in ['a'..'z', 'A'..'Z', '0'..'9', ' ', '-', ':']) then
      begin
        pay := '';
        Exit;
      end;
  end
  else Exit;

  i := pos('ophash', str) + 9;
  if (i > 9) then oph := copy(str, i, 24) else Exit;
end;

procedure TFormMain.GetAccountOperations();
var
  s, st, str, tx, pay, oph: string;
  i, j, blk: integer;
label
  GetMore;
begin
  Statusbar1.SimpleText := 'Last block: ' + IntToStr(FSeenBlk);
  blk := 0;
  str := SendRequest('getaccountoperations', '"account":' +  FSelectedAccount + ', "depth":5000, "start":0');

  i := pos('"ophash":', str) + 10;
  if i > 10 then blk := SwapEndian(Hex2Dec(copy(str, i, 8)))
  else Exit;

  if (FSeenBlk >= blk) then Exit;

GetMore:
  i := pos('[{', str);
  if (i > 0) then delete(str, 1, i);
  while str <> '' do
  begin
    i := pos('},', str);
    if (i > 0) then
    begin
      s := copy(str, 1, i);
      delete(str, 1, i + 2);
    end
    else
    begin
      i := pos('}],"id"', str);
      if (i > 0) then
      begin
        s := copy(str, 1, i);
        str := '';
      end;
    end;

    Tokenize(s, tx, pay, oph);

    if ((tx <> '') and (Length(Oph) = 24) and (pay <> '') and (Pos(' ', pay) > 0)) then
    begin

      j := SwapEndian(Hex2Dec(copy(oph, 1, 8)));

      if (FSeenBlk >= j) then
      begin
        FSeenBlk := blk;
        Exit;
      end;

      st := LowerCase(Trim(Copy(pay, 1, 4)));
      if st = 'forw' then process_forward(Oph, pay)
      else if st = 'escr' then process_escrow(oph, tx, pay)
      else if st = 'retu' then process_return(Oph, pay)
      else if st = 'lock' then process_lock(Oph, Pay)
      else process_error(oph, pay);

      Display('Sender: ' + IntToStr(SwapEndian(Hex2Dec(copy(oph, 9, 8)))) + ', Text: ' + tx + ', Payload: ' + pay);

    end; // if tokens
  end; // while

  Log('Warning - records could be missing'); // or goto GetMore
  FSeenBlk := blk;
end;

procedure TFormMain.Timer1Timer(Sender: TObject);
begin
  GetAccountOperations;
  Statusbar1.SimpleText := 'Last block: ' + IntToStr(FSeenBlk);
end;

end.

