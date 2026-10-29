# ForgeKit — jailed sideload toolkit dylib
# Plain dylib target: no MobileSubstrate/ElleKit/libhooker linkage, so the same
# binary works whether it is injected by a sideloader or by a jailbreak tweak loader.

TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = ForgeKit
ForgeKit_FILES = $(wildcard Sources/*.m)
ForgeKit_CFLAGS = -fobjc-arc -fvisibility=hidden -ISources -Wno-error=deprecated-declarations -Wno-error=unused-function -Wno-error=unused-variable -Wno-error=unused-const-variable
ForgeKit_FRAMEWORKS = Foundation UIKit CoreGraphics QuartzCore JavaScriptCore Security CoreImage AVFoundation
ForgeKit_LIBRARIES = z sqlite3
ForgeKit_USE_MODULES = 0
ForgeKit_INSTALL_PATH = @rpath

# Local Linux builds (iSH/Alpine) use the host clang + ld64.lld and cannot run
# Apple's strip/codesign; macOS builds keep the defaults.
ifeq ($(shell uname -s),Linux)
TARGET_STRIP = /bin/true
TARGET_CODESIGN = /bin/true
ForgeKit_CFLAGS += -fno-modules -g0
ForgeKit_LDFLAGS = -fuse-ld=lld -Wl,-platform_version,ios,14.0,16.5
ForgeKit_USE_MODULES = 0
endif

include $(THEOS_MAKE_PATH)/library.mk
