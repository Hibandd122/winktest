export THEOS = /opt/theos
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WinkVipSwitch
WinkVipSwitch_FILES = Tweak.xm
WinkVipSwitch_FRAMEWORKS = UIKit Foundation
WinkVipSwitch_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries
WinkVipSwitch_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
