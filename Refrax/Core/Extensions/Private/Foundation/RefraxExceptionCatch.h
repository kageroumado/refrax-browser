/**
 * RefraxExceptionCatch.h
 * Refrax Browser
 *
 * A thin @try/@catch bridge for the handful of Cocoa APIs that raise an
 * NSException rather than returning an error. Swift cannot catch ObjC
 * exceptions, so a raised NSException aborts the process; running the call
 * through this shim turns it into a value Swift can inspect and recover from.
 *
 * Example: CKContainer(identifier:) raises when the container is absent from
 * the app's entitlements (an unsigned or mis-provisioned build), which would
 * otherwise crash at launch.
 */

@import Foundation;

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

/// Runs @c block inside an ObjC @try/@catch, returning the raised NSException
/// or @c nil if the block completed normally.
NSException *_Nullable RefraxCatchingNSException(NS_NOESCAPE void (^block)(void));

NS_HEADER_AUDIT_END(nullability, sendability)
