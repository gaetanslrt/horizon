import 'package:country_codes/country_codes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:timezone/data/latest.dart' as tz;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
    ),
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  CountryCodes.init();
  tz.initializeTimeZones();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WeatherScreen(),
    );
  }
}

class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});

  @override
  _WeatherScreenState createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  String city = 'Loading...';
  Map<String, dynamic>? weatherData;
  Map<String, dynamic>? forecastData;
  bool isCelsius = true;
  int selectedDay = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkAndRequestLocationPermission(context);
    });
    fetchWeather();
  }

  Future<Position> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error('Location permissions are permanently denied');
    }

    return await Geolocator.getCurrentPosition();
  }

  Future<void> checkAndRequestLocationPermission(BuildContext context) async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      showDialog(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: Text('Location Services Disabled'),
          content: Text(
              'Please enable location services for accurate weather information.'),
          actions: [
            TextButton(
              child: Text('Enable'),
              onPressed: () async {
                Navigator.of(context).pop();
                await Geolocator.openLocationSettings();
                Geolocator.getServiceStatusStream()
                    .listen((ServiceStatus status) {
                  if (status == ServiceStatus.enabled) {
                    fetchWeather();
                  }
                });
              },
            ),
          ],
        ),
      );
    } else {
      fetchWeather();
    }
  }

  Future<void> fetchWeather() async {
    try {
      Position position = await _getCurrentLocation();
      Map<String, String> locationInfo = await _getCityName(position);
      String cityName = locationInfo['cityName'] ?? 'Unknown';
      String countryCode = locationInfo['countryCode'] ?? '';

      final url = Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=${position.latitude}&longitude=${position.longitude}&current_weather=true&daily=temperature_2m_max,temperature_2m_min,weathercode&temperature_unit=celsius&timezone=auto');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          weatherData = data['current_weather'];
          forecastData = data['daily'];
          city = '$cityName, $countryCode';
        });
      } else {
        throw Exception('Failed to load weather data');
      }
    } catch (e) {
      setState(() {
        weatherData = null;
        forecastData = null;
        city = 'Error: ${e.toString()}';
      });
      print('Error fetching weather: $e');
    }
  }

  String getWeatherEmoji(int weatherCode) {
    if (weatherCode >= 0 && weatherCode <= 3) return '☀️';
    if (weatherCode >= 45 && weatherCode <= 48) return '☁️';
    if (weatherCode >= 51 && weatherCode <= 57) return '🌦️';
    if (weatherCode >= 61 && weatherCode <= 67) return '🌧️';
    if (weatherCode >= 71 && weatherCode <= 77) return '❄️';
    if (weatherCode >= 80 && weatherCode <= 82) return '🌦️';
    if (weatherCode >= 85 && weatherCode <= 86) return '🌨️';
    if (weatherCode >= 95 && weatherCode <= 99) return '⛈️';
    return '❓';
  }

  Color getWeatherColor(int weatherCode) {
    if (weatherCode >= 0 && weatherCode <= 3) return Colors.orangeAccent;
    if (weatherCode >= 45 && weatherCode <= 48) return Colors.grey;
    if (weatherCode >= 51 && weatherCode <= 67) return Colors.blue;
    if (weatherCode >= 71 && weatherCode <= 77) return Colors.lightBlueAccent;
    if (weatherCode >= 80 && weatherCode <= 99) return Colors.deepPurpleAccent;
    return Colors.black;
  }

  Future<Map<String, String>> _getCityName(Position position) async {
    try {
      List<Placemark> placemarks =
          await placemarkFromCoordinates(position.latitude, position.longitude);
      if (placemarks.isNotEmpty) {
        String cityName = placemarks[0].locality ?? 'Unknown';
        String countryCode = placemarks[0].isoCountryCode ?? '';

        final details =
            CountryCodes.detailsForLocale(Locale('en', countryCode));
        String alpha3Code = details.alpha3Code ?? countryCode;

        return {
          'cityName': cityName,
          'countryCode': alpha3Code,
        };
      }
      return {'cityName': 'Unknown', 'countryCode': ''};
    } catch (e) {
      print('Error getting city name: $e');
      return {'cityName': 'Unknown', 'countryCode': ''};
    }
  }

  double celsiusToFahrenheit(double celsius) {
    return (celsius * 9 / 5) + 32;
  }

  String formatDate(String dateString) {
    DateTime date = DateTime.parse(dateString);
    return '${date.day}/${date.month}/${date.year}';
  }

  String getGreeting() {
    final now = DateTime.now();
    final hour = now.hour;

    if (hour >= 4 && hour < 12) {
      return 'Good Morning';
    } else if (hour >= 12 && hour < 18) {
      return 'Good Afternoon';
    } else {
      return 'Good Evening';
    }
  }

  @override
  Widget build(BuildContext context) {
    Color gradientColor = forecastData != null
        ? getWeatherColor(forecastData!['weathercode'][selectedDay])
        : Colors.black;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Column(
          children: [
            Padding(
              padding: EdgeInsets.only(top: 43.4),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [gradientColor, Colors.black],
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 100),
                const Spacer(),
                Center(
                  child: weatherData == null || forecastData == null
                      ? const CircularProgressIndicator()
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.location_on,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  city,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10.0),
                            Text(
                              getWeatherEmoji(
                                  forecastData!['weathercode'][selectedDay]),
                              style: const TextStyle(fontSize: 100),
                            ),
                            Text(
                              isCelsius
                                  ? '${forecastData!['temperature_2m_max'][selectedDay].round()}°C'
                                  : '${celsiusToFahrenheit(forecastData!['temperature_2m_max'][selectedDay]).round()}°F',
                              style: const TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              formatDate(forecastData!['time'][selectedDay]),
                              style: const TextStyle(
                                fontSize: 20,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  isCelsius = !isCelsius;
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white.withOpacity(0.3),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              child: Text(
                                isCelsius ? 'Switch to °F' : 'Switch to °C',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                ),
                const Spacer(),
                buildForecastCards(),
                const SizedBox(height: 25),
              ],
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).size.height * 0.1,
            left: 0,
            right: 0,
            child: Text(
              getGreeting(),
              style: const TextStyle(
                fontWeight: FontWeight.w300,
                fontSize: 40,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildForecastCards() {
    if (forecastData == null) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: SizedBox(
        height: 120,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: forecastData!['temperature_2m_max'].length,
          itemBuilder: (context, index) {
            return GestureDetector(
              onTap: () {
                setState(() {
                  selectedDay = index;
                });
              },
              child: Card(
                color: selectedDay == index
                    ? Colors.white.withOpacity(0.3)
                    : Colors.white.withOpacity(0.1),
                child: Container(
                  width: 100,
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        formatDate(forecastData!['time'][index]),
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        getWeatherEmoji(forecastData!['weathercode'][index]),
                        style: const TextStyle(fontSize: 24),
                      ),
                      Text(
                        isCelsius
                            ? '${forecastData!['temperature_2m_max'][index].round()}°C'
                            : '${celsiusToFahrenheit(forecastData!['temperature_2m_max'][index]).round()}°F',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
