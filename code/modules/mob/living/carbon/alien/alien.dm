#define LARVA_GROW_TIME 100

/mob/living/carbon/alien
	name = "alien" //The alien, not Alien
	voice_name = "alien"
	//speak_emote = list("hisses")
	icon = 'icons/mob/alien.dmi'
	gender = NEUTER
	dna = null

	mob_bump_flag = ALIEN
	mob_swap_flags = ALLMOBS
	mob_push_flags = ALLMOBS ^ ROBOT

	meat_type = /obj/item/weapon/reagent_containers/food/snacks/meat/xenomeat

	see_in_dark = 8

	var/plasma = 250
	var/max_plasma = 500
	var/neurotoxin_cooldown = 0

	var/obj/item/weapon/card/id/wear_id = null // Fix for station bounced radios -- Skie

	var/move_delay_add = 0 // movement delay to add

	status_flags = CANPARALYSE|CANPUSH|UNPACIFIABLE
	var/heal_rate = 2.5
	var/plasma_rate = 5

	var/oxygen_alert = 0
	var/toxins_alert = 0
	var/fire_alert = 0

	var/heat_protection = 0.5
	var/list/can_only_pickup = list(/obj/item/clothing/mask/facehugger, /obj/item/weapon/grab) //What types of object can the alien pick up?
	var/list/xeno_cult_items = list(/obj/item/weapon/melee/blood_dagger)

/mob/living/carbon/alien/New()
	add_language(LANGUAGE_XENO)
	default_language = all_languages[LANGUAGE_XENO]
	init_language = default_language
	. = ..()
	change_sight(adding = SEE_MOBS)

/mob/living/carbon/alien/update_perception()
	if(dark_plane)
		dark_plane.alphas["alien"] = 200
		dark_plane.colours = "#8C5E2F"
		client.color = list(
					1.2,0,0,0,
					0,1.3,0,0,
	 				0,0,1.3,0,
		 			0,-0.05,-0.1,1,
		 			0,0,0,0)

	check_dark_vision()

/mob/living/carbon/alien/AdjustPlasma(amount)
	plasma = min(max(plasma + amount,0),max_plasma) //upper limit of max_plasma, lower limit of 0
	updatePlasmaHUD()

/mob/living/carbon/alien/proc/updatePlasmaHUD()
	if(hud_used)
		if(!hud_used.vampire_blood_display)
			hud_used.plasma_hud()
			//hud_used.human_hud(hud_used.ui_style)
		hud_used.vampire_blood_display.maptext_width = WORLD_ICON_SIZE*2
		hud_used.vampire_blood_display.maptext_height = WORLD_ICON_SIZE
		hud_used.vampire_blood_display.maptext = "<div align='left' valign='top' style='position:relative; top:0px; left:6px'> P:<font color='#E9DAE9' size='1'>[plasma]</font><br>  / <font color='#BE7DBE' size='1'>[max_plasma]</font></div>"
	return

/*Code for aliens attacking aliens. Because aliens act on a hivemind, I don't see them as very aggressive with each other.
As such, they can either help or harm other aliens. Help works like the human help command while harm is a simple nibble.
In all, this is a lot like the monkey code. /N
*/

/mob/living/carbon/alien/attack_alien(mob/living/carbon/alien/humanoid/M)
	..()

	switch(M.a_intent)

		if(I_HELP)
			help_shake_act(M)
		if(I_GRAB)
			M.grab_mob(src)
		else
			M.unarmed_attack_mob(src)

/mob/living/carbon/alien/proc/getPlasma()
	return plasma

/mob/living/carbon/alien/eyecheck()
	return EYECHECK_FULL_PROTECTION

/mob/living/carbon/alien/earprot()
	return 1

// MULEBOT SMASH
/mob/living/carbon/alien/Crossed(var/atom/movable/AM)
	var/obj/machinery/bot/mulebot/MB = AM
	if(istype(MB))
		MB.RunOverCreature(src,"#00ff00")
		new /obj/effect/decal/cleanable/blood/xeno(src.loc)

/mob/living/carbon/alien/updatehealth()
	if(status_flags & GODMODE)
		health = maxHealth
		stat = CONSCIOUS
	else
		health = maxHealth - getOxyLoss() - getFireLoss() - getBruteLoss() - getCloneLoss()

/mob/living/carbon/alien/proc/handle_environment(var/datum/gas_mixture/environment)
	if(locate(/obj/effect/alien/weeds) in loc)
		if(health < maxHealth - getCloneLoss())
			adjustBruteLoss(-heal_rate)
			adjustFireLoss(-heal_rate)
			adjustOxyLoss(-heal_rate)
		AdjustPlasma(plasma_rate)

	if(!environment || (flags & INVULNERABLE))
		return
	var/loc_temp = T0C
	if(istype(loc, /obj/mecha))
		var/obj/mecha/M = loc
		loc_temp =  M.return_temperature()
	else if(istype(get_turf(src), /turf/space))
		var/turf/heat_turf = get_turf(src)
		loc_temp = heat_turf.temperature
	else if(istype(loc, /obj/machinery/atmospherics/unary/cryo_cell))
		var/obj/machinery/atmospherics/unary/cryo_cell/tube = loc
		loc_temp = tube.air_contents.temperature
	else
		loc_temp = environment.temperature

//	to_chat(world, "Loc temp: [loc_temp] - Body temp: [bodytemperature] - Fireloss: [getFireLoss()] - Fire protection: [heat_protection] - Location: [loc] - src: [src]")

	// Aliens are now weak to fire.

	//After then, it reacts to the surrounding atmosphere based on your thermal protection
	if(!on_fire) // If you're on fire, ignore local air temperature
		if(loc_temp > bodytemperature)
			//Place is hotter than we are
			var/thermal_protection = heat_protection //This returns a 0 - 1 value, which corresponds to the percentage of protection based on what you're wearing and what you're exposed to.
			if(thermal_protection < 1)
				bodytemperature += (1-thermal_protection) * ((loc_temp - bodytemperature) / BODYTEMP_HEAT_DIVISOR)
		else
			bodytemperature += 1 * ((loc_temp - bodytemperature) / BODYTEMP_HEAT_DIVISOR)
		//	bodytemperature -= max((loc_temp - bodytemperature / BODYTEMP_AUTORECOVERY_DIVISOR), BODYTEMP_AUTORECOVERY_MINIMUM)

	// +/- 50 degrees from 310.15K is the 'safe' zone, where no damage is dealt.
	if(bodytemperature > 360.15)
		//Body temperature is too hot.
		fire_alert = max(fire_alert, 1)
		switch(bodytemperature)
			if(360 to 400)
				apply_damage(HEAT_DAMAGE_LEVEL_1, BURN)
				fire_alert = max(fire_alert, 2)
			if(400 to 460)
				apply_damage(HEAT_DAMAGE_LEVEL_2, BURN)
				fire_alert = max(fire_alert, 2)
			if(460 to INFINITY)
				if(on_fire)
					apply_damage(HEAT_DAMAGE_LEVEL_3, BURN)
					fire_alert = max(fire_alert, 2)
				else
					apply_damage(HEAT_DAMAGE_LEVEL_2, BURN)
					fire_alert = max(fire_alert, 2)
	return

/mob/living/carbon/alien/proc/handle_mutations_and_radiation()


	if(getFireLoss())
		if((M_RESIST_HEAT in mutations) || prob(5))
			adjustFireLoss(-1)

	// Aliens love radiation nom nom nom
	if (radiation)
		if (radiation > 100)
			radiation = 100

		if (radiation < 0)
			radiation = 0

		switch(radiation)
			if(1 to 49)
				radiation--
				if(prob(25))
					AdjustPlasma(1)

			if(50 to 74)
				radiation -= 2
				AdjustPlasma(1)
				if(prob(5))
					radiation -= 5

			if(75 to 100)
				radiation -= 3
				AdjustPlasma(3)

/mob/living/carbon/alien/handle_fire()//Aliens on fire code
	if(..())
		return
	bodytemperature += BODYTEMP_HEATING_MAX //If you're on fire, you heat up!
	return

/mob/living/carbon/alien/dexterity_check()
	return FALSE

/mob/living/carbon/alien/Process_Spaceslipping()
	return 0 // Don't slip in space.

/mob/living/carbon/alien/Stat()

	if(statpanel("Status"))
		stat(null, "Intent: [a_intent]")
		stat(null, "Move Mode: [m_intent]")

	..()

	if(statpanel("Status"))
		stat(null, "Plasma Stored: [getPlasma()]/[max_plasma]")

		if(emergency_shuttle)
			if(emergency_shuttle.online && emergency_shuttle.location < 2)
				var/timeleft = emergency_shuttle.timeleft()
				if (timeleft)
					var/acronym = emergency_shuttle.location == 1 ? "ETD" : "ETA"
					stat(null, "[acronym]-[(timeleft / 60) % 60]:[add_zero(num2text(timeleft % 60), 2)]")

/mob/living/carbon/alien/Stun(amount)
	if(status_flags & CANSTUN)
		stunned = max(max(stunned,amount),0) //can't go below 0, getting a low amount of stun doesn't lower your current stun
	else
		// add some movement delay
		move_delay_add = min(move_delay_add + round(amount / 2), 10) // a maximum delay of 10
	return

/mob/living/carbon/alien/getDNA()
	return null

/mob/living/carbon/alien/setDNA()
	return

//This proc is NOT useless, we make it so that aliens have an halved siemens_coeff. Which means they take half damage
//I will personally find the retard who made all these VARIABLES into FUCKING CONSTANTS. THE FUCKING SOURCE AND THE SHOCK DAMAGE, CONSTANTS ? YOU THINK ?
/mob/living/carbon/alien/electrocute_act(const/shock_damage, const/obj/source, const/siemens_coeff = 1)

	var/damage = shock_damage * siemens_coeff

	if(damage <= 0)
		damage = 0

	if(take_overall_damage(0, damage, "[source]") == 0) // godmode
		return 0

	//src.burn_skin(shock_damage)
	//src.adjustFireLoss(shock_damage) //burn_skin will do this for us
	//src.updatehealth()

	visible_message( \
		"<span class='warning'>[src] was shocked by \the [source]!</span>", \
		"<span class='danger'>You feel a powerful shock course through your body!</span>", \
		"<span class='warning'>You hear a heavy electrical crack.</span>", \
		"<span class='notice'>[src] starts raving!</span>", \
		"<span class='notice'>You feel butterflies in your stomach!</span>", \
		"<span class='warning'>You hear a policeman whistling!</span>"
	)

	//if(src.stunned < shock_damage)	src.SetStunned(shock_damage)

	Stun(10) // this should work for now, more is really silly and makes you lay there forever

	//if(src.knockdown < 20*siemens_coeff)	SetKnockdown(20*siemens_coeff)

	Knockdown(10)

	spark(loc, 5)

	return damage/2 //Fuck this I'm not reworking your abortion of a proc, here's a copy-paste with not fucked code

/*----------------------------------------
Proc: AddInfectionImages()
Des: Gives the client of the alien an image on each infected mob.
----------------------------------------*/
/mob/living/carbon/alien/proc/AddInfectionImages()
	if (client)
		for (var/mob/living/C in mob_list)
			if(C.status_flags & XENO_HOST)
				var/obj/item/alien_embryo/A = locate() in C
				var/I = image('icons/mob/alien.dmi', loc = C, icon_state = "infected[A.stage]")
				client.images += I
	return


/*----------------------------------------
Proc: RemoveInfectionImages()
Des: Removes all infected images from the alien.
----------------------------------------*/
/mob/living/carbon/alien/proc/RemoveInfectionImages()
	if (client)
		for(var/image/I in client.images)
			if(dd_hasprefix_case(I.icon_state, "infected"))
				//del(I)
				client.images -= I
	return

/mob/living/carbon/alien/has_eyes()
	return 0
