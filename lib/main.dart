import 'package:flutter/material.dart';
import 'package:device_preview/device_preview.dart';
import 'package:invoicematcher/splash_screen.dart'; // Import the new splash screen file

// Set your backend URL. 
const String backendUrl = 'http://127.0.0.1:5000/match'; 

void main() {
  runApp(
    DevicePreview(
      enabled: true, // Set to false for production
      builder: (context) => const InvoiceMatcherApp(),
    ),
  );
}

class InvoiceMatcherApp extends StatelessWidget {
  const InvoiceMatcherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      useInheritedMediaQuery: true, 
      locale: DevicePreview.locale(context), 
      builder: DevicePreview.appBuilder,
      
      title: 'AI PO Matcher',
      theme: ThemeData(
        primarySwatch: Colors.blueGrey,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
      ),
      home: const SplashScreen(), 
    );
  }
}
