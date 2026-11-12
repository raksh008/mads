import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'branding.dart';
import 'finance/finance_screens.dart';

// ==========================================
// 1. SUPABASE INITIALIZATION
// ==========================================

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: const String.fromEnvironment(
      'RUVO_SUPABASE_URL',
      defaultValue: 'https://ddslubflmmwxbqsyzign.supabase.co',
    ),
    publishableKey: const String.fromEnvironment(
      'RUVO_SUPABASE_PUBLISHABLE_KEY',
      defaultValue: 'sb_publishable_eHYVT4wNzAOy_DCv59RSqQ_EkTPArIL',
    ),
  );

  runApp(const RuvoApp());
}

final supabase = Supabase.instance.client;

// ==========================================
// 4. MAIN APPLICATION
// ==========================================

class RuvoApp extends StatelessWidget {
  const RuvoApp({super.key});

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: forestGreen,
      brightness: brightness,
      surface: dark ? const Color(0xFF18242A) : Colors.white,
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? const Color(0xFF101A1F) : cream,
      useMaterial3: true,
      fontFamily: 'Arial',
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? const Color(0xFF101A1F) : cream,
        foregroundColor: dark ? Colors.white : ink,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: dark ? const Color(0xFF18242A) : Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
        margin: const EdgeInsets.only(bottom: 8),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF223138) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: forestGreen, width: 1.5),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
    valueListenable: ruvoThemeMode,
    builder: (context, themeMode, child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RUVO',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: themeMode,
      home: const AuthGate(),
    ),
  );
}

// ==========================================
// 5. AUTHENTICATION GATE
// ==========================================

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late User? currentUser;
  StreamSubscription<AuthState>? authSubscription;

  @override
  void initState() {
    super.initState();

    currentUser = supabase.auth.currentUser;

    authSubscription = supabase.auth.onAuthStateChange.listen((authState) {
      if (!mounted) return;

      setState(() {
        currentUser = authState.session?.user;
      });
    });
  }

  @override
  void dispose() {
    authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (currentUser == null) {
      return const WelcomeScreen();
    }

    return FinancialProfileGate(
      key: ValueKey(currentUser!.id),
      user: currentUser!,
    );
  }
}

// ==========================================
// 6. WELCOME SCREEN
// ==========================================

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),

              const RuvoLogo(fontSize: 28),

              const SizedBox(height: 25),

              const Text(
                'Give every\nrupee a purpose.',
                style: TextStyle(
                  fontSize: 38,
                  height: 1.2,
                  fontWeight: FontWeight.bold,
                  color: forestGreen,
                ),
              ),

              const SizedBox(height: 18),

              const Text(
                'Make smarter financial decisions '
                'before you spend.',
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: Colors.black54,
                ),
              ),

              const Spacer(),

              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SignUpScreen()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: forestGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: const Text('Create account'),
                ),
              ),

              const SizedBox(height: 14),

              SizedBox(
                width: double.infinity,
                height: 55,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: forestGreen,
                    side: const BorderSide(color: forestGreen),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: const Text('Log in'),
                ),
              ),

              const SizedBox(height: 25),

              const Center(
                child: Text(
                  'Your money. Your decisions.',
                  style: TextStyle(fontSize: 12, color: Colors.black45),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 7. SIGN UP SCREEN
// ==========================================

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoading = false;
  bool hidePassword = true;

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> signUp() async {
    final name = nameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text;

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      showMessage('Please complete all fields.');
      return;
    }

    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      showMessage('Please enter a valid email address.');
      return;
    }

    if (password.length < 8) {
      showMessage('Password must contain at least 8 characters.');
      return;
    }

    setState(() => isLoading = true);

    try {
      final response = await supabase.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': name},
      );

      if (!mounted) return;

      // Always return the user to the login screen after sign-up.
      // If Supabase created a session immediately, sign it out first so
      // the user can explicitly log in after completing the sign-up flow.
      if (response.session != null) {
        await supabase.auth.signOut();
      }

      if (!mounted) return;

      showMessage(
        'Account created. If email confirmation is enabled, verify your email, then log in.',
      );

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => LoginScreen(initialEmail: email)),
        (route) => false,
      );
    } on AuthException catch (error) {
      showMessage(error.message);
    } catch (error) {
      showMessage('Something went wrong. Please try again.');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: cream, foregroundColor: forestGreen),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(25),
          children: [
            const RuvoLogo(fontSize: 22),

            const SizedBox(height: 35),

            const Text(
              'Create your\naccount.',
              style: TextStyle(
                fontSize: 32,
                height: 1.2,
                fontWeight: FontWeight.bold,
                color: forestGreen,
              ),
            ),

            const SizedBox(height: 12),

            const Text(
              'Start building a better relationship with money.',
              style: TextStyle(color: Colors.black54),
            ),

            const SizedBox(height: 30),

            buildField('Full name', 'Enter your full name', nameController),

            buildField(
              'Email address',
              'you@example.com',
              emailController,
              type: TextInputType.emailAddress,
            ),

            buildField(
              'Password',
              'Minimum 8 characters',
              passwordController,
              obscure: hidePassword,
              suffix: IconButton(
                onPressed: () {
                  setState(() {
                    hidePassword = !hidePassword;
                  });
                },
                icon: Icon(
                  hidePassword ? Icons.visibility_off : Icons.visibility,
                ),
              ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              height: 55,
              child: ElevatedButton(
                onPressed: isLoading ? null : signUp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: forestGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Create account'),
              ),
            ),

            const SizedBox(height: 22),

            Center(
              child: TextButton(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
                child: const Text(
                  'Already have an account? Log in',
                  style: TextStyle(color: forestGreen),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildField(
    String label,
    String hint,
    TextEditingController controller, {
    TextInputType type = TextInputType.text,
    bool obscure = false,
    Widget? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: forestGreen,
            ),
          ),
          const SizedBox(height: 9),
          TextField(
            controller: controller,
            keyboardType: type,
            obscureText: obscure,
            decoration: InputDecoration(
              hintText: hint,
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              suffixIcon: suffix,
              contentPadding: const EdgeInsets.all(17),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 8. LOGIN SCREEN
// ==========================================

class LoginScreen extends StatefulWidget {
  final String? initialEmail;

  const LoginScreen({super.key, this.initialEmail});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController emailController;
  final passwordController = TextEditingController();

  bool isLoading = false;
  bool hidePassword = true;

  @override
  void initState() {
    super.initState();

    emailController = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> login() async {
    final email = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      showMessage('Enter your email and password.');
      return;
    }

    setState(() => isLoading = true);

    try {
      await supabase.auth.signInWithPassword(email: email, password: password);

      if (!mounted) return;

      Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthException catch (error) {
      showMessage(error.message);
    } catch (error) {
      showMessage('Unable to log in. Please try again.');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> resetPassword() async {
    final email = emailController.text.trim();

    if (email.isEmpty) {
      showMessage('Enter your email address first.');
      return;
    }

    try {
      await supabase.auth.resetPasswordForEmail(email);

      if (!mounted) return;

      showMessage('Password reset instructions sent to your email.');
    } on AuthException catch (error) {
      showMessage(error.message);
    }
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: cream, foregroundColor: forestGreen),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(25),
          children: [
            const RuvoLogo(fontSize: 22),

            const SizedBox(height: 40),

            const Text(
              'Welcome\nback.',
              style: TextStyle(
                fontSize: 34,
                height: 1.2,
                fontWeight: FontWeight.bold,
                color: forestGreen,
              ),
            ),

            const SizedBox(height: 12),

            const Text(
              'Your money, with a plan.',
              style: TextStyle(color: Colors.black54),
            ),

            const SizedBox(height: 35),

            const Text(
              'Email address',
              style: TextStyle(fontWeight: FontWeight.w600, color: forestGreen),
            ),

            const SizedBox(height: 9),

            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: 'you@example.com',
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 22),

            const Text(
              'Password',
              style: TextStyle(fontWeight: FontWeight.w600, color: forestGreen),
            ),

            const SizedBox(height: 9),

            TextField(
              controller: passwordController,
              obscureText: hidePassword,
              decoration: InputDecoration(
                hintText: 'Enter your password',
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() {
                      hidePassword = !hidePassword;
                    });
                  },
                  icon: Icon(
                    hidePassword ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: resetPassword,
                child: const Text(
                  'Forgot password?',
                  style: TextStyle(color: forestGreen),
                ),
              ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              height: 55,
              child: ElevatedButton(
                onPressed: isLoading ? null : login,
                style: ElevatedButton.styleFrom(
                  backgroundColor: forestGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Log in'),
              ),
            ),

            const SizedBox(height: 20),

            Center(
              child: TextButton(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const SignUpScreen()),
                  );
                },
                child: const Text(
                  'New to RUVO? Create an account',
                  style: TextStyle(color: forestGreen),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
