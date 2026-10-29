# ForgeKit — jailed sideload toolkit dylib
# Plain dylib target: no MobileSubstrate/ElleKit/libhooker linkage, so the same
# binary works whether it is injected by a sideloader or by a jailbreak tweak loader.

TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = ForgeKit
ForgeKit_FILES = $(wildcard Sources/*.m)
ForgeKit_CFLAGS = -fobjc-arc -fvisibility=hidden -ISources
ForgeKit_FRAMEWORKS = Foundation UIKit CoreGraphics QuartzCore JavaScriptCore Security CoreImage AVFoundation
ForgeKit_LIBRARIES = z sqlite3
ForgeKit_INSTALL_PATH = /usr/lib

include $(THEOS_MAKE_PATH)/library.mk
