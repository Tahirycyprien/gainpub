// GainPub : regarde des pubs, gagne des points, retire tes gains.
// Version Supabase (aucune modification nécessaire).

import 'dart:async';
import 'package:android_id/android_id.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kSupabaseUrl = 'https://irzvkcevdlsaqqkmhypa.supabase.co';
const kSupabaseKey = 'sb_publishable_4Bj7YIwAB16D2MCRtqvczA_AENaMado';

// ID du bloc d'annonces AdMob (pub avec récompense).
const kRewardedAdId = 'ca-app-pub-6535401140220842/9288181044';
const kDailyLimit = 20;
const kUnlockViews = 200;
const kMinWithdraw = [1000, 5000, 10000];

final messengerKey = GlobalKey<ScaffoldMessengerState>();

void snack(String m) =>
    messengerKey.currentState?.showSnackBar(SnackBar(content: Text(m)));

SupabaseClient get sb => Supabase.instance.client;

String errMsg(Object e) {
  if (e is PostgrestException) return e.message;
  if (e is AuthException) return e.message;
  return 'Une erreur est survenue, vérifie ta connexion';
}

Future<Map<String, dynamic>> rpc(String fn, [Map<String, dynamic>? params]) async {
  final r = await sb.rpc(fn, params: params);
  return Map<String, dynamic>.from(r as Map);
}

Future<String> deviceId() async => (await AndroidId().getId()) ?? 'unknown';

String todayUtc() => DateTime.now().toUtc().toIso8601String().substring(0, 10);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: kSupabaseUrl, anonKey: kSupabaseKey);
  await MobileAds.instance.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'GainPub',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: messengerKey,
        theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
        home: StreamBuilder<AuthState>(
          stream: sb.auth.onAuthStateChange,
          builder: (c, s) =>
              sb.auth.currentSession == null ? const AuthPage() : const HomePage(),
        ),
      );
}

// ------------------------------------------------------------------
// Inscription / connexion
// ------------------------------------------------------------------
class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final email = TextEditingController();
  final pass = TextEditingController();
  final code = TextEditingController();
  bool signup = true;
  bool busy = false;

  Future<void> submit() async {
    setState(() => busy = true);
    try {
      if (signup) {
        final res = await sb.auth.signUp(
          email: email.text.trim(),
          password: pass.text,
          data: {'referral': code.text.trim()},
        );
        if (res.session == null) {
          snack('Compte créé. Confirme ton email, puis connecte-toi.');
        }
      } else {
        await sb.auth.signInWithPassword(
            email: email.text.trim(), password: pass.text);
      }
    } catch (e) {
      snack(errMsg(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const SizedBox(height: 40),
          const Icon(Icons.monetization_on, size: 72, color: Colors.green),
          const SizedBox(height: 8),
          Text('GainPub',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          if (signup)
            const Text('Inscris-toi et reçois 200 points de bonus 🎁',
                textAlign: TextAlign.center),
          const SizedBox(height: 24),
          TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email')),
          TextField(
              controller: pass,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Mot de passe (6 caractères minimum)')),
          if (signup)
            TextField(
                controller: code,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                    labelText: 'Code de parrainage (facultatif)')),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: busy ? null : submit,
            child: Text(busy ? '...' : (signup ? "S'inscrire" : 'Se connecter')),
          ),
          TextButton(
            onPressed: () => setState(() => signup = !signup),
            child: Text(signup ? 'Déjà un compte ? Connexion' : 'Créer un compte'),
          ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------
// Coque de l'appli
// ------------------------------------------------------------------
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  Map<String, dynamic>? u;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _boot();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => refresh());
  }

  Future<void> _boot() async {
    try {
      final meta = sb.auth.currentUser?.userMetadata;
      await rpc('init_user', {
        'p_device': await deviceId(),
        'p_referral': (meta?['referral'] ?? '').toString(),
        'p_country': null,
      });
    } catch (e) {
      snack(errMsg(e));
      await sb.auth.signOut();
      return;
    }
    await refresh();
  }

  Future<void> refresh() async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final r = await sb.from('profiles').select().eq('id', uid).maybeSingle();
      if (mounted) setState(() => u = r);
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = u;
    if (data == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: tab, children: [
          DashboardPage(u: data, onRefresh: refresh),
          ReferralPage(u: data),
          WithdrawPage(u: data, onRefresh: refresh),
          ProfilePage(u: data),
        ]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) {
          setState(() => tab = i);
          refresh();
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Accueil'),
          NavigationDestination(icon: Icon(Icons.group_add), label: 'Parrainage'),
          NavigationDestination(
              icon: Icon(Icons.account_balance_wallet), label: 'Retrait'),
          NavigationDestination(icon: Icon(Icons.person), label: 'Profil'),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------
// Tableau de bord
// ------------------------------------------------------------------
class DashboardPage extends StatefulWidget {
  final Map<String, dynamic> u;
  final Future<void> Function() onRefresh;
  const DashboardPage({super.key, required this.u, required this.onRefresh});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  RewardedAd? _ad;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    RewardedAd.load(
      adUnitId: kRewardedAdId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => setState(() => _ad = ad),
        onAdFailedToLoad: (_) => _ad = null,
      ),
    );
  }

  void _watch() {
    final ad = _ad;
    if (ad == null) {
      snack("La pub n'est pas prête, réessaie dans un instant");
      _load();
      return;
    }
    setState(() => _ad = null);
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _load();
      },
    );
    // AdMob confirme la vue directement à notre serveur (SSV)
    ad.setServerSideOptions(
        ServerSideVerificationOptions(userId: sb.auth.currentUser!.id));
    ad.show(onUserEarnedReward: (_, __) {
      snack('Pub validée, tes points arrivent dans quelques secondes ✅');
      for (final s in [4, 8, 14]) {
        Future.delayed(Duration(seconds: s), widget.onRefresh);
      }
    });
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.u;
    final pts = (u['points'] ?? 0) as int;
    final total = (u['views_total'] ?? 0) as int;
    final today = u['views_day'] == todayUtc() ? (u['views_today'] ?? 0) as int : 0;
    final unlocked = u['bonus_unlocked'] == true;

    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            const Text('Ton solde'),
            Text('$pts points',
                style: Theme.of(context).textTheme.headlineLarge),
            Text('≈ ${(pts / 1000).toStringAsFixed(2)} \$'),
          ]),
        ),
      ),
      if (!unlocked)
        Card(
          color: Colors.amber.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('🎁 Bonus de ${u['pending_bonus']} points à débloquer'),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                  value: (total / kUnlockViews).clamp(0.0, 1.0)),
              const SizedBox(height: 4),
              Text('$total / $kUnlockViews pubs regardées'),
            ]),
          ),
        ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: today >= kDailyLimit ? null : _watch,
        icon: const Icon(Icons.play_circle),
        label: Text(today >= kDailyLimit
            ? 'Reviens demain !'
            : 'Regarder une pub (+1 point)'),
        style: FilledButton.styleFrom(padding: const EdgeInsets.all(18)),
      ),
      const SizedBox(height: 8),
      Text("Aujourd'hui : $today / $kDailyLimit pubs", textAlign: TextAlign.center),
      Text('Total : $total pubs regardées', textAlign: TextAlign.center),
    ]);
  }
}

// ------------------------------------------------------------------
// Parrainage
// ------------------------------------------------------------------
class ReferralPage extends StatelessWidget {
  final Map<String, dynamic> u;
  const ReferralPage({super.key, required this.u});

  Future<int> _count() async {
    final uid = sb.auth.currentUser!.id;
    final r = await sb.from('referrals').select('id').eq('referrer', uid);
    return (r as List).length;
  }

  @override
  Widget build(BuildContext context) {
    final code = (u['referral_code'] ?? '').toString();
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Invite tes amis', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text("Tu gagnes 100 points chaque fois qu'un ami inscrit avec ton code "
          'atteint 200 pubs regardées.'),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
              child: SelectableText(code,
                  style: Theme.of(context).textTheme.headlineMedium)),
        ),
      ),
      FilledButton.icon(
        onPressed: () => Share.share(
            "Gagne de l'argent en regardant des pubs avec GainPub ! "
            "Utilise mon code $code à l'inscription."),
        icon: const Icon(Icons.share),
        label: const Text('Partager mon code'),
      ),
      const SizedBox(height: 16),
      FutureBuilder<int>(
        future: _count(),
        builder: (c, s) => Text('Amis actifs parrainés : ${s.data ?? 0}',
            textAlign: TextAlign.center),
      ),
    ]);
  }
}

// ------------------------------------------------------------------
// Retrait
// ------------------------------------------------------------------
class WithdrawPage extends StatefulWidget {
  final Map<String, dynamic> u;
  final Future<void> Function() onRefresh;
  const WithdrawPage({super.key, required this.u, required this.onRefresh});
  @override
  State<WithdrawPage> createState() => _WithdrawPageState();
}

class _WithdrawPageState extends State<WithdrawPage> {
  String method = 'google_play';
  final paypal = TextEditingController();
  bool busy = false;
  int _reload = 0;

  Future<void> _withdraw() async {
    setState(() => busy = true);
    try {
      final r = await rpc('request_withdrawal', {
        'p_method': method,
        'p_account': method == 'paypal' ? paypal.text.trim() : null,
      });
      snack('Demande envoyée : ${r['usd']} \$');
      await widget.onRefresh();
      if (mounted) setState(() => _reload++);
    } catch (e) {
      snack(errMsg(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<List<dynamic>> _history() async {
    final uid = sb.auth.currentUser!.id;
    return await sb
        .from('withdrawals')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(20) as List<dynamic>;
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.u;
    final pts = (u['points'] ?? 0) as int;
    final count = (u['withdrawals_count'] ?? 0) as int;
    final min = kMinWithdraw[count > 2 ? 2 : count];

    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Retirer mes gains', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      Text('Solde : $pts points • Minimum pour ce retrait : $min points '
          '(${min / 1000} \$)'),
      const Text(
          'Les minimums augmentent à chaque retrait : 1 \$, puis 5 \$, puis 10 \$.'),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        value: method,
        decoration: const InputDecoration(labelText: 'Méthode'),
        items: const [
          DropdownMenuItem(value: 'google_play', child: Text('Solde Google Play')),
          DropdownMenuItem(value: 'paypal', child: Text('PayPal')),
        ],
        onChanged: (v) => setState(() => method = v!),
      ),
      if (method == 'paypal')
        TextField(
            controller: paypal,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email PayPal')),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: (busy || pts < min) ? null : _withdraw,
        child: Text(
            pts < min ? 'Encore ${min - pts} points' : 'Demander le retrait'),
      ),
      const SizedBox(height: 24),
      Text('Historique', style: Theme.of(context).textTheme.titleMedium),
      FutureBuilder<List<dynamic>>(
        key: ValueKey(_reload),
        future: _history(),
        builder: (c, s) {
          final rows = s.data ?? [];
          if (rows.isEmpty) return const Text("Aucun retrait pour l'instant");
          return Column(
            children: rows.map((w) {
              return ListTile(
                title: Text('${w['usd']} \$ • ${w['method']}'),
                trailing: Text('${w['status']}'),
              );
            }).toList(),
          );
        },
      ),
    ]);
  }
}

// ------------------------------------------------------------------
// Profil
// ------------------------------------------------------------------
class ProfilePage extends StatelessWidget {
  final Map<String, dynamic> u;
  const ProfilePage({super.key, required this.u});

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      ListTile(
          leading: const Icon(Icons.email),
          title: Text(sb.auth.currentUser?.email ?? '')),
      const Divider(),
      const Text('Règles', style: TextStyle(fontWeight: FontWeight.bold)),
      const Text('• 1 pub regardée = 1 point (1000 points = 1 \$)\n'
          "• Maximum 20 pubs par jour\n"
          "• Le bonus d'inscription se débloque après 200 pubs\n"
          '• Un seul compte par appareil\n'
          '• Les retraits sont vérifiés avant paiement'),
      const SizedBox(height: 24),
      OutlinedButton(
        onPressed: () => sb.auth.signOut(),
        child: const Text('Se déconnecter'),
      ),
    ]);
  }
}
