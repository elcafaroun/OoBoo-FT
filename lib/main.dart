import 'package:fada/screens/structures_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // ✅ Import de Provider
import 'providers/cart_provider.dart'; // ✅ Import de votre CartProvider
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/reset_password_screen.dart';
import 'screens/cart_screen.dart'; // ✅ Import de l'écran Panier

void main() {
  runApp(
    // ✅ On enveloppe l'application avec MultiProvider
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CartProvider()),
        // Vous pourrez ajouter d'autres providers ici plus tard (ex: UserProvider)
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Fada - Gestion de Structures',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
        useMaterial3: true,
        // Personnalisation globale des champs de saisie
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.transparent),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.orange, width: 2),
          ),
        ),
      ),

      // 👇 Route initiale
      initialRoute: '/login',

      routes: {
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/reset-password': (context) => const ResetPasswordScreen(),
        '/structures': (context) => const StructuresScreen(),
        '/cart': (context) => const CartScreen(), // ✅ Route vers le panier
      },
    );
  }
}