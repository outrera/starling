// =================================================================================================
//
//	Starling Framework
//	Copyright 2011 Gamua OG. All Rights Reserved.
//
//	This program is free software. You can redistribute and/or modify it
//	in accordance with the terms of the accompanying license agreement.
//
// =================================================================================================


package starling.animation;
import openfl.errors.ArgumentError;
import starling.events.Event;
import starling.events.EventDispatcher;

/** A Tween animates numeric properties of objects. It uses different transition functions 
 *  to give the animations various styles.
 *  
 *  <p>The primary use of this class is to do standard animations like movement, fading, 
 *  rotation, etc. But there are no limits on what to animate; as long as the property you want
 *  to animate is numeric (<code>int, uint, Number</code>), the tween can handle it. For a list 
 *  of available Transition types, look at the "Transitions" class.</p> 
 *  
 *  <p>Here is an example of a tween that moves an object to the right, rotates it, and 
 *  fades it out:</p>
 *  
 *  <listing>
 *  var tween:Tween = new Tween(object, 2.0, Transitions.EASE_IN_OUT);
 *  tween.animate("x", object.x + 50);
 *  tween.animate("rotation", deg2rad(45));
 *  tween.fadeTo(0);    // equivalent to 'animate("alpha", 0)'
 *  Starling.juggler.add(tween);</listing> 
 *  
 *  <p>Note that the object is added to a juggler at the end of this sample. That's because a 
 *  tween will only be executed if its "advanceTime" method is executed regularly - the 
 *  juggler will do that for you, and will remove the tween when it is finished.</p>
 *  
 *  @see Juggler
 *  @see Transitions
 */ 
class Tween extends EventDispatcher implements IAnimatable
{
    private var mTarget:Dynamic;
    private var mTransitionFunc:Float->Float;
    private var mTransitionName:String;
    
    private var mProperties:Array<String>;
    private var mStartValues:Array<Float>;
    private var mEndValues:Array<Float>;

    private var mOnStart:Array<Dynamic>->Void;
    private var mOnUpdate:Array<Dynamic>->Void;
    private var mOnRepeat:Array<Dynamic>->Void;
    private var mOnComplete:Array<Dynamic>->Void;  
    
    private var mOnStartArgs:Array<Dynamic>;
    private var mOnUpdateArgs:Array<Dynamic>;
    private var mOnRepeatArgs:Array<Dynamic>;
    private var mOnCompleteArgs:Array<Dynamic>;
    
    private var mTotalTime:Float;
    private var mCurrentTime:Float;
    private var mProgress:Float;
    private var mDelay:Float;
    private var mRoundToInt:Bool;
    private var mNextTween:Tween;
    private var mRepeatCount:Int;
    private var mRepeatDelay:Float;
    private var mReverse:Bool;
    private var mCurrentCycle:Int;
    
    /** Creates a tween with a target, duration (in seconds) and a transition function.
     *  @param target the object that you want to animate
     *  @param time the duration of the Tween (in seconds)
     *  @param transition can be either a String (e.g. one of the constants defined in the
     *         Transitions class) or a function. Look up the 'Transitions' class for a   
     *         documentation about the required function signature. */ 
    public function new(target:Dynamic, time:Float, transition:Dynamic="linear")        
    {
         reset(target, time, transition);
    }

    /** Resets the tween to its default values. Useful for pooling tweens. */
    public function reset(target:Dynamic, time:Float, transition:Dynamic="linear"):Tween
    {
        mTarget = target;
        mCurrentTime = 0.0;
        mTotalTime = Math.max(0.0001, time);
        mProgress = 0.0;
        mDelay = mRepeatDelay = 0.0;
        mOnStart = mOnUpdate = mOnComplete = null;
        mOnStartArgs = mOnUpdateArgs = mOnCompleteArgs = null;
        mRoundToInt = mReverse = false;
        mRepeatCount = 1;
        mCurrentCycle = -1;
        
        if (Std.is(transition, String))
            this.transition = cast(transition, String);
        else if (Reflect.isFunction(transition))
            this.transitionFunc = transition;
        else 
            throw new ArgumentError("Transition must be either a string or a function");
        
        if (mProperties != null)  mProperties = []; else mProperties  = new Array<String>();
        if (mStartValues != null) mStartValues = []; else mStartValues = new Array<Float>();
        if (mEndValues != null)   mEndValues = []; else mEndValues   = new Array<Float>();
        
        return this;
    }
    
    /** Animates the property of the target to a certain value. You can call this method multiple
     *  times on one tween. */
    public function animate(property:String, endValue:Float):Void
    {
        if (mTarget == null) return; // tweening null just does nothing.
               
        mProperties.push(property);
        mStartValues.push(Math.NaN);
        mEndValues.push(endValue);
    }
    
    /** Animates the 'scaleX' and 'scaleY' properties of an object simultaneously. */
    public function scaleTo(factor:Float):Void
    {
        animate("scaleX", factor);
        animate("scaleY", factor);
    }
    
    /** Animates the 'x' and 'y' properties of an object simultaneously. */
    public function moveTo(x:Float, y:Float):Void
    {
        animate("x", x);
        animate("y", y);
    }
    
    /** Animates the 'alpha' property of an object to a certain target value. */ 
    public function fadeTo(alpha:Float):Void
    {
        animate("alpha", alpha);
    }
    
    /** @inheritDoc */
    public function advanceTime(time:Float):Void
    {
        if (time == 0 || (mRepeatCount == 1 && mCurrentTime == mTotalTime)) return;
        
        var i:Int;
        var previousTime:Float = mCurrentTime;
        var restTime:Float = mTotalTime - mCurrentTime;
        var carryOverTime:Float = time > restTime ? time - restTime : 0.0;
        
        mCurrentTime += time;
        
        if (mCurrentTime <= 0) 
            return; // the delay is not over yet
        else if (mCurrentTime > mTotalTime) 
            mCurrentTime = mTotalTime;
        
        if (mCurrentCycle < 0 && previousTime <= 0 && mCurrentTime > 0)
        {
            mCurrentCycle++;
            if (mOnStart != null) mOnStart(mOnStartArgs);
        }

        var ratio:Float = mCurrentTime / mTotalTime;
        var reversed:Bool = mReverse && (mCurrentCycle % 2 == 1);
        var numProperties:Int = mStartValues.length;
        mProgress = reversed ? mTransitionFunc(1.0 - ratio) : mTransitionFunc(ratio);

        //for (i=0; i<numProperties; ++i)
        for(i in 0 ... numProperties)
        {                
            if (mStartValues[i] != mStartValues[i]) // isNaN check - "isNaN" causes allocation! 
                mStartValues[i] = cast(Reflect.getProperty(mTarget, mProperties[i]), Float);
            
            var startValue:Float = mStartValues[i];
            var endValue:Float = mEndValues[i];
            var delta:Float = endValue - startValue;
            var currentValue:Float = startValue + mProgress * delta;
            
            if (mRoundToInt) currentValue = Math.round(currentValue);
            Reflect.setProperty(mTarget, mProperties[i], currentValue);
        }

        if (mOnUpdate != null) 
            mOnUpdate(mOnUpdateArgs);
        
        if (previousTime < mTotalTime && mCurrentTime >= mTotalTime)
        {
            if (mRepeatCount == 0 || mRepeatCount > 1)
            {
                mCurrentTime = -mRepeatDelay;
                mCurrentCycle++;
                if (mRepeatCount > 1) mRepeatCount--;
                if (mOnRepeat != null) mOnRepeat(mOnRepeatArgs);
            }
            else
            {
                // save callback & args: they might be changed through an event listener
                var onComplete:Array<Dynamic>->Void = mOnComplete;
                var onCompleteArgs:Array<Dynamic> = mOnCompleteArgs;
                
                // in the 'onComplete' callback, people might want to call "tween.reset" and
                // add it to another juggler; so this event has to be dispatched *before*
                // executing 'onComplete'.
                dispatchEventWith(Event.REMOVE_FROM_JUGGLER);
                if (onComplete != null) onComplete(onCompleteArgs);
            }
        }
        
        if (carryOverTime != 0) 
            advanceTime(carryOverTime);
    }
    
    /** The end value a certain property is animated to. Throws an ArgumentError if the 
     *  property is not being animated. */
    public function getEndValue(property:String):Float
    {
        var index:Int = mProperties.indexOf(property);
        if (index == -1) throw new ArgumentError("The property '" + property + "' is not animated");
        else return mEndValues[index];
    }
    
    /** Indicates if the tween is finished. */
    public var isComplete(get, never):Bool;
    public function get_isComplete():Bool 
    { 
        return mCurrentTime >= mTotalTime && mRepeatCount == 1; 
    }        
    
    /** The target object that is animated. */
    public var target(get, never):Dynamic;
    public function get_target():Dynamic { return mTarget; }
    
    /** The transition method used for the animation. @see Transitions */
    public var transition(get, set):String;
    public function get_transition():String { return mTransitionName; }
    public function set_transition(value:String):String 
    { 
        mTransitionName = value;
        mTransitionFunc = Transitions.getTransition(value);
        
        if (mTransitionFunc == null)
            throw new ArgumentError("Invalid transiton: " + value);
        return mTransitionName;
    }
    
    /** The actual transition function used for the animation. */
    public var transitionFunc(get, set):Float->Float;
    public function get_transitionFunc():Float->Float { return mTransitionFunc; }
    public function set_transitionFunc(value:Float->Float):Float->Float
    {
        mTransitionName = "custom";
        mTransitionFunc = value;
        return value;
    }
    
    /** The total time the tween will take per repetition (in seconds). */
    public var totalTime(get, never):Float;
    public function get_totalTime():Float { return mTotalTime; }
    
    /** The time that has passed since the tween was created (in seconds). */
    public var currentTime(get, never):Float;
    public function get_currentTime():Float { return mCurrentTime; }
    
    /** The current progress between 0 and 1, as calculated by the transition function. */
    public var progress(get, never):Float;
    public function get_progress():Float { return mProgress; } 
    
    /** The delay before the tween is started (in seconds). @default 0 */
    public var delay(get, set):Float;
    public function get_delay():Float { return mDelay; }
    public function set_delay(value:Float):Float 
    { 
        mCurrentTime = mCurrentTime + mDelay - value;
        mDelay = value;
        return mDelay;
    }
    
    /** The number of times the tween will be executed. 
     *  Set to '0' to tween indefinitely. @default 1 */
    public var repeatCount(get, set):Int;
    public function get_repeatCount():Int { return mRepeatCount; }
    public function set_repeatCount(value:Int):Int { return mRepeatCount = value; }
    
    /** The amount of time to wait between repeat cycles (in seconds). @default 0 */
    public var repeatDelay(get, set):Float;
    public function get_repeatDelay():Float { return mRepeatDelay; }
    public function set_repeatDelay(value:Float):Float { return mRepeatDelay = value; }
    
    /** Indicates if the tween should be reversed when it is repeating. If enabled, 
     *  every second repetition will be reversed. @default false */
    public var reverse(get, set):Bool;
    public function get_reverse():Bool { return mReverse; }
    public function set_reverse(value:Bool):Bool { return mReverse = value; }
    
    /** Indicates if the numeric values should be cast to Integers. @default false */
    public var roundToInt(get, set):Bool;
    public function get_roundToInt():Bool { return mRoundToInt; }
    public function set_roundToInt(value:Bool):Bool { return mRoundToInt = value; }        
    
    /** A function that will be called when the tween starts (after a possible delay). */
    public var onStart(get, set):Array<Dynamic>->Void;
    public function get_onStart():Array<Dynamic>->Void { return mOnStart; }
    public function set_onStart(value:Array<Dynamic>->Void):Array<Dynamic>->Void { return mOnStart = value; }
    
    /** A function that will be called each time the tween is advanced. */
    public var onUpdate(get, set):Array<Dynamic>->Void;
    public function get_onUpdate():Array<Dynamic>->Void { return mOnUpdate; }
    public function set_onUpdate(value:Array<Dynamic>->Void):Array<Dynamic>->Void { return mOnUpdate = value; }
    
    /** A function that will be called each time the tween finishes one repetition
     *  (except the last, which will trigger 'onComplete'). */
    public var onRepeat(get, set):Array<Dynamic>->Void;
    public function get_onRepeat():Array<Dynamic>->Void { return mOnRepeat; }
    public function set_onRepeat(value:Array<Dynamic>->Void):Array<Dynamic>->Void { return mOnRepeat = value; }
    
    /** A function that will be called when the tween is complete. */
    public var onComplete(get, set):Array<Dynamic>->Void;
    public function get_onComplete():Array<Dynamic>->Void { return mOnComplete; }
    public function set_onComplete(value:Array<Dynamic>->Void):Array<Dynamic>->Void { return mOnComplete = value; }
    
    /** The arguments that will be passed to the 'onStart' function. */
    public var onStartArgs(get, set):Array<Dynamic>;
    public function get_onStartArgs():Array<Dynamic> { return mOnStartArgs; }
    public function set_onStartArgs(value:Array<Dynamic>):Array<Dynamic> { return mOnStartArgs = value; }
    
    /** The arguments that will be passed to the 'onUpdate' function. */
    public var onUpdateArgs:Array<Dynamic>;
    public function get_onUpdateArgs():Array<Dynamic> { return mOnUpdateArgs; }
    public function set_onUpdateArgs(value:Array<Dynamic>):Void { mOnUpdateArgs = value; }
    
    /** The arguments that will be passed to the 'onRepeat' function. */
    public var onRepeatArgs(get, set):Array<Dynamic>;
    public function get_onRepeatArgs():Array<Dynamic> { return mOnRepeatArgs; }
    public function set_onRepeatArgs(value:Array<Dynamic>):Array<Dynamic> { return mOnRepeatArgs = value; }
    
    /** The arguments that will be passed to the 'onComplete' function. */
    public var onCompleteArgs(get, set):Array<Dynamic>;
    public function get_onCompleteArgs():Array<Dynamic> { return mOnCompleteArgs; }
    public function set_onCompleteArgs(value:Array<Dynamic>):Array<Dynamic> { return mOnCompleteArgs = value; }
    
    /** Another tween that will be started (i.e. added to the same juggler) as soon as 
     *  this tween is completed. */
    public var nextTween(get, set):Tween;
    public function get_nextTween():Tween { return mNextTween; }
    public function set_nextTween(value:Tween):Tween { return mNextTween = value; }
    
    // tween pooling
    
    private static var sTweenPool:Array<Tween> = new Array<Tween>();
    
    /** @private */
    public static function fromPool(target:Dynamic, time:Float, 
                                               transition:Dynamic="linear"):Tween
    {
        if (sTweenPool.length != 0) return sTweenPool.pop().reset(target, time, transition);
        else return new Tween(target, time, transition);
    }
    
    /** @private */
    public static function toPool(tween:Tween):Void
    {
        // reset any object-references, to make sure we don't prevent any garbage collection
        tween.mOnStart = tween.mOnUpdate = tween.mOnRepeat = tween.mOnComplete = null;
        tween.mOnStartArgs = tween.mOnUpdateArgs = tween.mOnRepeatArgs = tween.mOnCompleteArgs = null;
        tween.mTarget = null;
        tween.mTransitionFunc = null;
        tween.removeEventListeners();
        sTweenPool.push(tween);
    }
}