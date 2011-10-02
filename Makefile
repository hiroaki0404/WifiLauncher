# $Id$

APPBASE=work/WifiLauncher.app/Contents
CODEDIR=$(APPBASE)/MacOS
RESDIR=$(APPBASE)/Resources
SRC=src/loginwisper.rb src/wifilauncher.pl src/hotspot.rb src/startup src/livedoorweb.rb
CONF=sample/sample.wificmd sample/sample.wifispot.yam
CTRL=jp.group.wifilauncher.plist

appdirs:
	-mkdir -p $(CODEDIR)/lib
	-mkdir -p $(RESDIR)

appcopy: appdirs
	-cp -R lib $(CODEDIR)
	-cp $(SRC) $(CODEDIR)
	-cp $(CONF) $(RESDIR)
	-cp $(CTRL) $(RESDIR)
	-cp Info.plist $(APPBASE)
	-tiff2icns wifilauncher.tiff $(RESDIR)/WifiLauncher.icns

app: appdirs appcopy

clean:
	-rm -fr work/
