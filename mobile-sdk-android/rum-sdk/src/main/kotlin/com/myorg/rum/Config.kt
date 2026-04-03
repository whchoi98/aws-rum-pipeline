package com.myorg.rum

/**
 * RUM SDK 설정 데이터 클래스.
 *
 * @param endpoint        이벤트 수집 API 엔드포인트 (예: https://api.example.com)
 * @param apiKey          API 인증 키
 * @param appVersion      앱 버전 문자열 (예: "2.1.0")
 * @param sampleRate      이벤트 샘플링 비율 (0.0 ~ 1.0, 기본값 1.0 = 100%)
 * @param flushIntervalMs 자동 플러시 주기 (밀리초, 기본값 30초)
 * @param maxBatchSize    단일 배치 최대 이벤트 수 (기본값 10)
 * @param debug           디버그 로그 출력 여부
 */
data class Config(
    val endpoint: String,
    val apiKey: String,
    val appVersion: String,
    val sampleRate: Double = 1.0,
    val flushIntervalMs: Long = 30_000L,
    val maxBatchSize: Int = 10,
    val debug: Boolean = false
) {
    init {
        require(endpoint.isNotBlank()) { "endpoint 는 비어 있을 수 없습니다." }
        require(apiKey.isNotBlank()) { "apiKey 는 비어 있을 수 없습니다." }
        require(sampleRate in 0.0..1.0) { "sampleRate 는 0.0 ~ 1.0 범위여야 합니다." }
        require(flushIntervalMs > 0) { "flushIntervalMs 는 양수여야 합니다." }
        require(maxBatchSize > 0) { "maxBatchSize 는 양수여야 합니다." }
    }
}
