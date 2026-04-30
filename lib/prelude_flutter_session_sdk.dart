/// Prelude Flutter Session SDK.
///
/// Public Dart API surface for the Prelude session-based
/// authentication SDK. Bridges to the native iOS
/// (`PreludeSessionClient` in `PreludeSession`) and Android
/// (`PreludeSessionClient` in `so.prelude.android:sessions`)
/// session SDKs.
library;

export 'src/client.dart' show PreludeSessionClient;

export 'src/types/endpoint.dart' show Endpoint;
export 'src/types/errors.dart'
    show
        BadRequestException,
        ForbiddenException,
        InsufficientScopeException,
        InternalServerErrorException,
        InvalidChallengeTokenException,
        InvalidConfigurationException,
        InvalidOTPCodeException,
        InvalidPasswordException,
        MissingChallengeTokenException,
        NetworkException,
        PreludeSessionException,
        PreludeSessionGenericException,
        RateLimitedException,
        RefreshFailedException,
        TimeoutException,
        UnauthorizedException;
export 'src/types/identifier.dart'
    show PreludeIdentifier, PreludeIdentifierType;
export 'src/types/json_value.dart'
    show
        PreludeJSONArray,
        PreludeJSONBool,
        PreludeJSONDouble,
        PreludeJSONInt,
        PreludeJSONNull,
        PreludeJSONObject,
        PreludeJSONString,
        PreludeJSONValue;
export 'src/types/otp.dart' show StartOTPLoginOptions;
export 'src/types/password.dart'
    show
        LoginWithPasswordOptions,
        PreludePasswordCompliancy,
        PreludePasswordCompliancyCriterion,
        PreludePasswordCompliancyResult,
        PreludePasswordCompliancyResults;
export 'src/types/profile.dart' show PreludeProfile;
export 'src/types/redacted_string.dart' show RedactedString;
export 'src/types/step_up.dart' show StepUpChallenge, StepUpStatus;
export 'src/types/user.dart' show PreludeUser;
