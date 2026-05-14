if( NOT APPLE )
	return()
endif()

enable_language( OBJCXX )

set( APPLE_CONTOUR_DETECTION_SOURCES
	AppleContourDetection.h
	AppleContourDetection.mm
)

add_library( ffgl-plugin-apple-contour-detection STATIC )
add_library( ffgl::plugin::apple_contour_detection ALIAS ffgl-plugin-apple-contour-detection )
target_sources( ffgl-plugin-apple-contour-detection PRIVATE ${APPLE_CONTOUR_DETECTION_SOURCES} )
target_compile_definitions( ffgl-plugin-apple-contour-detection PRIVATE GL_SILENCE_DEPRECATION )
target_link_libraries( ffgl-plugin-apple-contour-detection PRIVATE
	ffgl::sdk
	"-framework Foundation"
	"-framework CoreVideo"
	"-framework Vision"
	"-framework OpenGL"
)

add_library( AppleContourDetection MODULE
	${APPLE_CONTOUR_DETECTION_SOURCES}
)
target_compile_definitions( AppleContourDetection PRIVATE GL_SILENCE_DEPRECATION )
target_link_libraries( AppleContourDetection PRIVATE
	ffgl::sdk
	"-framework Foundation"
	"-framework CoreVideo"
	"-framework Vision"
	"-framework OpenGL"
)
set_target_properties( AppleContourDetection PROPERTIES
	BUNDLE TRUE
	BUNDLE_EXTENSION bundle
	PREFIX ""
	OUTPUT_NAME AppleContourDetection
	MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in"
)

install(
	TARGETS     ffgl-plugin-apple-contour-detection AppleContourDetection
	EXPORT      ffgl--plugin-apple-contour-detection-targets
	DESTINATION ${CMAKE_INSTALL_LIBDIR}
)
