if( NOT APPLE )
	return()
endif()

enable_language( OBJCXX )

set(APPLE_PERSON_SEGMENTATION_SOURCES
	ApplePersonSegmentation.h
	ApplePersonSegmentation.mm
)

add_library(ffgl-plugin-apple-person-segmentation STATIC)
add_library(ffgl::plugin::apple_person_segmentation ALIAS ffgl-plugin-apple-person-segmentation)
target_sources(ffgl-plugin-apple-person-segmentation PRIVATE ${APPLE_PERSON_SEGMENTATION_SOURCES})
target_compile_definitions(ffgl-plugin-apple-person-segmentation PRIVATE GL_SILENCE_DEPRECATION)
target_link_libraries(ffgl-plugin-apple-person-segmentation PRIVATE
	ffgl::sdk
	"-framework Foundation"
	"-framework CoreVideo"
	"-framework Vision"
	"-framework OpenGL"
)

add_library(ApplePersonSegmentation MODULE
	${APPLE_PERSON_SEGMENTATION_SOURCES}
)
target_compile_definitions(ApplePersonSegmentation PRIVATE GL_SILENCE_DEPRECATION)
target_link_libraries(ApplePersonSegmentation PRIVATE
	ffgl::sdk
	"-framework Foundation"
	"-framework CoreVideo"
	"-framework Vision"
	"-framework OpenGL"
)
set_target_properties(ApplePersonSegmentation PROPERTIES
	BUNDLE TRUE
	BUNDLE_EXTENSION bundle
	PREFIX ""
	OUTPUT_NAME ApplePersonSegmentation
	MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in"
)

install(
	TARGETS     ffgl-plugin-apple-person-segmentation ApplePersonSegmentation
	EXPORT      ffgl--plugin-apple-person-segmentation-targets
	DESTINATION ${CMAKE_INSTALL_LIBDIR}
)
