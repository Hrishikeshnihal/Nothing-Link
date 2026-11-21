@echo off
set "JAVA_HOME=C:\Users\Rushikesh\.jdks\jdk17.0.21_0"
set "ANDROID_HOME=C:\Users\Rushikesh\AppData\Local\Android\Sdk"
set "PATH=%JAVA_HOME%\bin;%PATH%"

"C:\Users\Rushikesh\.gradle\wrapper\dists\gradle-8.7-bin\bhs2wmbdwecv87pi65oeuq5iu\gradle-8.7\bin\gradle.bat" %*
