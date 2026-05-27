export THEOS = /opt/theos
TWEAK_NAME = WinkVipSwitch
WinkVipSwitch_FILES = Tweak.xm
WinkVipSwitch_FRAMEWORKS = UIKit Foundation
WinkVipSwitch_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries
WinkVipSwitch_CFLAGS = -fobjc-arc
WinkVipSwitch_LDFLAGS = -Wl,-undefined,dynamic_lookup

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
