/// Prelude Flutter Auth SDK.
///
/// Public Dart API surface for Prelude Auth on iOS and Android.
library;

export 'src/client.dart' show PreludeAuthClient;

export 'src/types/endpoint.dart' show Endpoint;
export 'src/types/errors.dart'
    show
        BadRequestException,
        ConflictException,
        ExpiredChallengeTokenException,
        ForbiddenException,
        InsufficientScopeException,
        InternalServerErrorException,
        InvalidChallengeTokenException,
        InvalidConfigurationException,
        InvalidOTPCodeException,
        InvalidPasswordException,
        MissingChallengeTokenException,
        NetworkException,
        NotFoundException,
        PreludeAuthException,
        PreludeAuthGenericException,
        RateLimitedException,
        RefreshFailedException,
        TimeoutException,
        TokenReusedException,
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
export 'src/types/sessions.dart'
    show
        PreludeDeviceType,
        PreludeListSessionsOptions,
        PreludeListSessionsResponse,
        PreludeRevokeTarget,
        PreludeSessionView;
export 'src/types/step_up.dart' show StepUpChallenge, StepUpStatus;
export 'src/types/user.dart' show PreludeUser;
