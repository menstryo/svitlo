TARGET := iphone:clang:9.3:6.0
ARCHS = armv7
INSTALL_TARGET_PROCESSES = Svitlo

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Svitlo
Svitlo_FILES = main.m SVStore.m SVTimelineView.m SVListViewController.m SVSettingsViewController.m SVMainViewController.m
Svitlo_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore
Svitlo_CFLAGS = -fno-objc-arc -fno-modules -Wno-deprecated-declarations -Wno-unused-variable -Wno-deprecated-module-dot-map

include $(THEOS_MAKE_PATH)/application.mk
