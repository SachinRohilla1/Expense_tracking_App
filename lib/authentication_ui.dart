import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'auth_service.dart';
import 'device_authentication.dart';

typedef DashboardBuilder = Widget Function(
  AppUser user,
  AuthService authService,
);

class AuthenticationErrorScreen extends StatelessWidget {
  const AuthenticationErrorScreen({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 56),
                const SizedBox(height: 16),
                Text(
                  'Could not open your local account',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({
    required this.authService,
    required this.deviceAuthenticator,
    required this.dashboardBuilder,
    super.key,
  });

  final AuthService authService;
  final DeviceAuthenticator deviceAuthenticator;
  final DashboardBuilder dashboardBuilder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppUser?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AuthenticationErrorScreen(
            message: 'Could not check your local account: ${snapshot.error}',
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          return SignInScreen(authService: authService);
        }
        return DeviceLockScreen(
          key: ValueKey(user.id),
          user: user,
          authService: authService,
          deviceAuthenticator: deviceAuthenticator,
          dashboardBuilder: dashboardBuilder,
        );
      },
    );
  }
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({required this.authService, super.key});

  final AuthService authService;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isCreatingAccount = false;
  bool _isBusy = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });

    try {
      if (_isCreatingAccount) {
        await widget.authService.createAccount(
          _emailController.text.trim(),
          _passwordController.text,
        );
      } else {
        await widget.authService.signIn(
          _emailController.text.trim(),
          _passwordController.text,
        );
      }
    } on LocalAuthException catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.message);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _errorMessage = 'Could not access local account: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty || !email.contains('@')) {
      return 'Enter a valid email address';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if ((value ?? '').length < 8) {
      return 'Password must be at least 8 characters';
    }
    return null;
  }

  String? _validateConfirmation(String? value) {
    if (value != _passwordController.text) return 'Passwords do not match';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final title = _isCreatingAccount ? 'Create your account' : 'Welcome back';

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          child: Container(
                            padding: const EdgeInsets.all(15),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Icon(
                              Icons.account_balance_wallet_outlined,
                              size: 32,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your account stays on this device. There is no cloud sync or password reset.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 28),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            border: OutlineInputBorder(),
                          ),
                          validator: _validateEmail,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          autofillHints: [
                            _isCreatingAccount
                                ? AutofillHints.newPassword
                                : AutofillHints.password,
                          ],
                          textInputAction: _isCreatingAccount
                              ? TextInputAction.next
                              : TextInputAction.done,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            border: OutlineInputBorder(),
                          ),
                          validator: _validatePassword,
                          onFieldSubmitted: (_) {
                            if (!_isCreatingAccount && !_isBusy) _submit();
                          },
                        ),
                        if (_isCreatingAccount) ...[
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _confirmPasswordController,
                            obscureText: true,
                            autofillHints: const [AutofillHints.newPassword],
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(
                              labelText: 'Confirm password',
                              border: OutlineInputBorder(),
                            ),
                            validator: _validateConfirmation,
                            onFieldSubmitted: (_) {
                              if (!_isBusy) _submit();
                            },
                          ),
                        ],
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _isBusy ? null : _submit,
                          child: _isBusy
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  _isCreatingAccount
                                      ? 'Create account'
                                      : 'Sign in',
                                ),
                        ),
                        TextButton(
                          onPressed: _isBusy
                              ? null
                              : () {
                                  setState(() {
                                    _isCreatingAccount = !_isCreatingAccount;
                                    _errorMessage = null;
                                  });
                                },
                          child: Text(
                            _isCreatingAccount
                                ? 'Already have an account? Sign in'
                                : 'New here? Create an account',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DeviceLockScreen extends StatefulWidget {
  const DeviceLockScreen({
    required this.user,
    required this.authService,
    required this.deviceAuthenticator,
    required this.dashboardBuilder,
    super.key,
  });

  final AppUser user;
  final AuthService authService;
  final DeviceAuthenticator deviceAuthenticator;
  final DashboardBuilder dashboardBuilder;

  @override
  State<DeviceLockScreen> createState() => _DeviceLockScreenState();
}

class _DeviceLockScreenState extends State<DeviceLockScreen>
    with WidgetsBindingObserver {
  final _webPasswordController = TextEditingController();
  bool _isLocked = true;
  bool _isAuthenticating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
    }
  }

  @override
  void dispose() {
    _webPasswordController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.inactive ||
            state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused) &&
        !_isLocked) {
      setState(() => _isLocked = true);
    } else if (state == AppLifecycleState.resumed &&
        _isLocked &&
        !_isAuthenticating &&
        !kIsWeb) {
      _unlock();
    }
  }

  Future<void> _unlock() async {
    if (_isAuthenticating || !_isLocked) return;
    setState(() {
      _isAuthenticating = true;
      _errorMessage = null;
    });
    try {
      final authenticated = await widget.deviceAuthenticator.authenticate();
      if (!mounted) return;
      setState(() {
        _isLocked = !authenticated;
        if (!authenticated) {
          _errorMessage = 'Authentication was not completed. Try again.';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Could not authenticate: $error');
    } finally {
      if (mounted) setState(() => _isAuthenticating = false);
    }
  }

  Future<void> _signOut() async {
    setState(() {
      _isAuthenticating = true;
      _errorMessage = null;
    });
    try {
      await widget.authService.signOut();
    } catch (error) {
      if (mounted) setState(() => _errorMessage = 'Could not sign out: $error');
    } finally {
      if (mounted) setState(() => _isAuthenticating = false);
    }
  }

  Future<void> _unlockWithPassword() async {
    if (_webPasswordController.text.isEmpty) {
      setState(() => _errorMessage = 'Enter your account password.');
      return;
    }

    setState(() {
      _isAuthenticating = true;
      _errorMessage = null;
    });
    try {
      await widget.authService.reauthenticate(
        widget.user.email,
        _webPasswordController.text,
      );
      if (mounted) setState(() => _isLocked = false);
      _webPasswordController.clear();
    } on LocalAuthException catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.message);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not verify your account: $error');
      }
    } finally {
      if (mounted) setState(() => _isAuthenticating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLocked) {
      return widget.dashboardBuilder(widget.user, widget.authService);
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 56),
                  const SizedBox(height: 20),
                  Text(
                    'Unlock Expense Tracker',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    kIsWeb ? 'Enter your account password to continue.' : 'Use your device biometrics or screen-lock PIN to continue.',
                    textAlign: TextAlign.center,
                  ),
                  if (kIsWeb) ...[
                    const SizedBox(height: 20),
                    TextField(
                      controller: _webPasswordController,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) {
                        if (!_isAuthenticating) _unlockWithPassword();
                      },
                    ),
                  ],
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _isAuthenticating
                        ? null
                        : kIsWeb
                        ? _unlockWithPassword
                        : _unlock,
                    icon: Icon(kIsWeb ? Icons.lock_open : Icons.fingerprint),
                    label: Text(
                      _isAuthenticating
                          ? 'Authenticating...'
                          : kIsWeb
                          ? 'Unlock with password'
                          : 'Unlock',
                    ),
                  ),
                  TextButton(
                    onPressed: _isAuthenticating ? null : _signOut,
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
