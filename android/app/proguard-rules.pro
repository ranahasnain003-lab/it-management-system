# Release-build (R8) keep rules.
#
# Firebase finds its components at start-up by reflecting on every
# ComponentRegistrar named in the merged AndroidManifest and calling its
# no-argument constructor. Nothing in the code references those constructors
# directly, so R8 removes them when it shrinks the release build. The classes
# survive, the constructors do not, and start-up then logs:
#
#   ComponentDiscovery: Could not instantiate
#     com.google.firebase.appcheck.FirebaseAppCheckRegistrar
#   Caused by: java.lang.NoSuchMethodException: <init> []
#
# which leaves Firebase App Check unregistered and unable to issue a token.
# Keeping the constructor is enough; the classes are still shrunk and
# obfuscated as usual.
-keep class * implements com.google.firebase.components.ComponentRegistrar {
    public <init>();
}
