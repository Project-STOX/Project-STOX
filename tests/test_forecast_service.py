from app.services.forecast_service import ForecastService


def test_moving_average_empty_series_returns_zero() -> None:
    assert ForecastService._moving_average([]) == 0.0


def test_moving_average_returns_expected_value() -> None:
    assert ForecastService._moving_average([10, 20, 30, 40]) == 25.0


def test_exponential_smoothing_empty_series_returns_zero() -> None:
    assert ForecastService._exponential_smoothing([], alpha=0.3) == 0.0


def test_exponential_smoothing_returns_expected_value() -> None:
    # Start=10 -> 15 -> 22.5 when alpha=0.5 over [10, 20, 30]
    result = ForecastService._exponential_smoothing([10, 20, 30], alpha=0.5)
    assert result == 22.5


def test_exponential_smoothing_low_alpha_weights_history_more() -> None:
    low_alpha = ForecastService._exponential_smoothing([10, 50, 90], alpha=0.1)
    high_alpha = ForecastService._exponential_smoothing([10, 50, 90], alpha=0.9)
    assert low_alpha < high_alpha
