/obj/machinery/power/am_control_unit
	name = "antimatter control unit"
	desc = "This device injects antimatter into connected shielding units. Wrench the device to set it up."
	icon = 'icons/obj/machines/new_ame.dmi'
	icon_state = "control"
	var/icon_mod = "on" // on, critical, or fuck
	var/old_icon_mod = "on"
	anchored = 0
	density = 1
	use_power = MACHINE_POWER_USE_IDLE
	idle_power_usage = 100
	active_power_usage = 1000

	var/list/obj/machinery/am_shielding/linked_shielding
	var/list/obj/machinery/am_shielding/linked_cores
	var/obj/item/weapon/am_containment/fueljar
	var/update_shield_icons = 0
	var/stability = 100
	var/exploding = 0
	var/exploded = 0

	var/active = 0//On or not
	var/fuel_injection = 2//How much fuel to inject
	var/shield_icon_delay = 0//delays resetting for a short time
	var/reported_core_efficiency = 0

	var/power_cycle = 0
	var/power_cycle_delay = 4//How many ticks till produce_power is called
	var/stored_core_stability = 0
	var/stored_core_stability_delay = 0

	var/stored_power = 0//Power to deploy per tick


/obj/machinery/power/am_control_unit/New()
	..()
	linked_shielding = list()
	linked_cores = list()


/obj/machinery/power/am_control_unit/Destroy()//Perhaps damage and run stability checks rather than just del on the others
	for(var/obj/machinery/am_shielding/AMS in linked_shielding)
		AMS.control_unit = null
		qdel(AMS)
	for(var/obj/machinery/am_shielding/AMS in linked_cores)
		AMS.control_unit = null
		qdel(AMS)
	qdel(fueljar)
	fueljar = null
	..()


/obj/machinery/power/am_control_unit/process()
	if(exploding && !exploded)
		message_admins("AME explosion at ([x],[y],[z] - <A HREF='?_src_=holder;adminplayerobservecoodjump=1;X=[x];Y=[y];Z=[z]'>JMP</a>) - Last touched by [fingerprintslast]",0,1)
		exploded=1
		explosion(get_turf(src),8,10,12,15, whodunnit = get_mob_by_key(fingerprintslast))
		if(src)
			qdel(src)

	if(update_shield_icons && !shield_icon_delay)
		check_shield_icons()
		update_shield_icons = 0

	if(stat & (FORCEDISABLE|NOPOWER|BROKEN) || !active)//can update the icons even without power
		return

	if(!fueljar || fueljar.fuel <= 0)//No fuel but we are on, shutdown
		toggle_power()
		//Angry buzz or such here
		return

	check_core_stability()

	add_avail(stored_power)

	power_cycle++
	if(power_cycle >= power_cycle_delay)
		produce_power()
		power_cycle = 0

	return


/obj/machinery/power/am_control_unit/proc/produce_power()
	playsound(src, arcanetampered ? 'sound/effects/bang.ogg' : 'sound/effects/explosionsmallfar.ogg', 25, 1)
	var/core_power = reported_core_efficiency//Effectively how much fuel we can safely deal with
	if(core_power <= 0)
		return 0//Something is wrong
	var/core_damage = 0
	var/fuel = fueljar.usefuel(fuel_injection)

	stored_power = (fuel/core_power)*fuel*20000 // Was 200000, was too much. New value run past Aurx. - N3X
	//Now check if the cores could deal with it safely, this is done after so you can overload for more power if needed, still a bad idea
	if(fuel > (2*core_power))//More fuel has been put in than the current cores can deal with
		if(prob(50))
			core_damage = 1//Small chance of damage
		if((fuel-core_power) > 5)
			core_damage = 5//Now its really starting to overload the cores
		if((fuel-core_power) > 10)
			core_damage = 20//Welp now you did it, they wont stand much of this
		if(core_damage == 0)
			return
		for(var/obj/machinery/am_shielding/AMS in linked_cores)
			AMS.stability -= core_damage
			AMS.check_stability(1)
		playsound(src, 'sound/effects/bang.ogg', 50, 1)
	return

/obj/machinery/power/am_control_unit/conveyor_act(var/atom/movable/AM, var/obj/machinery/conveyor/CB)
	if(istype(AM,/obj/item/weapon/am_containment))
		if(fueljar)
			return FALSE
		var/obj/item/weapon/am_containment/AMC = AM
		var/mob/last_touched = AMC.fingerprintslast
		fueljar = AMC
		overlays += "control-[AMC.icon_state]"
		playsound(src, 'sound/items/Deconstruct.ogg', 50, 1)
		AMC.forceMove(src)
		message_admins("AME loaded with fuel by [last_touched ? "[last_touched.real_name] ([last_touched.key])" : "a conveyor"] at ([x],[y],[z] - <A HREF='?_src_=holder;adminplayerobservecoodjump=1;X=[x];Y=[y];Z=[z]'>JMP</a>)",0,1)
		visible_message("The conveyor loads an [AMC.name] into the [src.name].")
		return TRUE
	return FALSE

/obj/machinery/power/am_control_unit/emp_act(severity)
	switch(severity)
		if(1)
			if(active)
				toggle_power()
			stability -= rand(15,30)
		if(2)
			if(active)
				toggle_power()
			stability -= rand(10,20)
	..()
	return 0


/obj/machinery/power/am_control_unit/blob_act()
	stability -= 20
	if(prob(100-stability))//Might infect the rest of the machine
		for(var/obj/machinery/am_shielding/AMS in linked_cores)
			AMS.blob_act(2)
		for(var/obj/machinery/am_shielding/AMS in linked_shielding)
			AMS.blob_act(1)
		qdel(src)
		return
	check_stability()
	return


/obj/machinery/power/am_control_unit/ex_act(severity)
	switch(severity)
		if(1.0)
			stability -= 60
		if(2.0)
			stability -= 40
		if(3.0)
			stability -= 20
	check_stability()
	return


/obj/machinery/power/am_control_unit/bullet_act(var/obj/item/projectile/Proj)
	if(Proj.flag != "bullet")
		stability -= Proj.force
	return ..()

/obj/machinery/power/am_control_unit/power_change()
	..()
	if(stat & (FORCEDISABLE|NOPOWER) && active)
		toggle_power()
	return


/obj/machinery/power/am_control_unit/update_icon()
	if(active)
		icon_state = "control_[icon_mod]"
	else icon_state = "control"
	//No other icons for it atm


/obj/machinery/power/am_control_unit/attackby(obj/item/W, mob/user)
	if(!istype(W) || !user)
		return
	if(W.is_wrench(user))
		if(!anchored)
			W.playtoolsound(src, 75)
			user.visible_message("[user.name] secures the [src.name] to the floor.", \
				"You secure the anchor bolts to the floor.", \
				"You hear a ratchet")
			src.anchored = 1
			update_shield_icons = 2
			check_shield_icons()
			connect_to_network()
		else if(!linked_shielding.len > 0)
			W.playtoolsound(src, 75)
			user.visible_message("[user.name] unsecures the [src.name].", \
				"You remove the anchor bolts.", \
				"You hear a ratchet")
			src.anchored = 0
			disconnect_from_network()
		else
			to_chat(user, "<span class='warning'>Once bolted and linked to a shielding unit it the [src.name] is unable to be moved!</span>")
		return

	if(istype(W, /obj/item/weapon/am_containment))
		if(fueljar)
			to_chat(user, "<span class='warning'>There is already a [fueljar] inside!</span>")
			return
		fueljar = W
		overlays += "control-[W.icon_state]"
		playsound(src, 'sound/items/Deconstruct.ogg', 50, 1)
		if(user.client)
			user.client.screen -= W
		user.u_equip(W,1)
		W.forceMove(src)
		user.update_icons()
		message_admins("AME loaded with fuel by [user.real_name] ([user.key]) at ([x],[y],[z] - <A HREF='?_src_=holder;adminplayerobservecoodjump=1;X=[x];Y=[y];Z=[z]'>JMP</a>)",0,1)
		user.visible_message("[user.name] loads an [W.name] into the [src.name].", \
				"You load an [W.name].", \
				"You hear a thunk.")
		return

	if(W.force >= 20)
		user.do_attack_animation(src, W)
		playsound(src, 'sound/items/metal_impact.ogg', 75, 1)
		shake(1, 3)
		user.delayNextAttack(8)
		visible_message("<span class='warning'>\The [user] hits \the [src] with \a [W]!</span>", \
					"<span class='warning'>You hit \the [src] with your [W]!</span>", \
					"You hear something metallic being hit.")
		stability -= W.force/2
		check_stability()
	..()
	return


/obj/machinery/power/am_control_unit/attack_hand(mob/user as mob)
	if(anchored)
		interact(user)
	return


/obj/machinery/power/am_control_unit/proc/add_shielding(var/obj/machinery/am_shielding/AMS, var/AMS_linking = 0)
	if(!istype(AMS))
		return 0
	if(!anchored)
		return 0
	if(!AMS_linking && !AMS.link_control(src))
		return 0
	if(!(AMS in linked_shielding))
		linked_shielding.Add(AMS)
	update_shield_icons = 1
	return 1


/obj/machinery/power/am_control_unit/proc/remove_shielding(var/obj/machinery/am_shielding/AMS)
	if(!istype(AMS))
		return 0
	linked_shielding.Remove(AMS)
	update_shield_icons = 2
	if(active)
		toggle_power()
	return 1


/obj/machinery/power/am_control_unit/proc/check_stability()//TODO: make it break when low also might want to add a way to fix it like a part or such that can be replaced
	if(stability <= 0)
		qdel(src)
	return


/obj/machinery/power/am_control_unit/proc/toggle_power()
	active = !active
	if(active)
		playsound(src, 'sound/effects/fall.ogg', 50, 1)
		use_power = MACHINE_POWER_USE_ACTIVE
		visible_message("[bicon(src)] The [src.name] starts up.")
	else
		playsound(src, 'sound/effects/fall2.ogg', 50, 1)
		use_power = MACHINE_POWER_USE_IDLE
		visible_message("[bicon(src)] The [src.name] shuts down.")
	for(var/obj/machinery/am_shielding/AMS in linked_cores)
		AMS.update_icon()
	update_icon()
	return


/obj/machinery/power/am_control_unit/proc/check_shield_icons()//Forces icon_update for all shields
	if(shield_icon_delay)
		return
	shield_icon_delay = 1
	if(update_shield_icons == 2)//2 means to clear everything and rebuild
		for(var/obj/machinery/am_shielding/neighbor in cardinalrange(loc))
			if(!neighbor.control_unit)
				linked_shielding += neighbor
		for(var/obj/machinery/am_shielding/AMS in linked_shielding)
			if(AMS.processing)
				AMS.shutdown_core()
			AMS.control_unit = null
			spawn(10)
				AMS.controllerscan()
				AMS.assimilate()
		linked_shielding = list()

	else
		for(var/obj/machinery/am_shielding/AMS in linked_shielding)
			AMS.update_icon()
	sleep(20)
	shield_icon_delay = 0


/obj/machinery/power/am_control_unit/proc/check_core_stability()
	//if(stored_core_stability_delay || linked_cores.len <= 0)	return
	if(linked_cores.len <=0)
		return
	//stored_core_stability_delay = 1
	stored_core_stability = 0
	for(var/obj/machinery/am_shielding/AMS in linked_cores)
		stored_core_stability += AMS.stability
	stored_core_stability/=linked_cores.len
	if(arcanetampered)
		icon_mod="fuck"
	else
		switch(stored_core_stability)
			if(0 to 24)
				icon_mod="fuck"
			if(25 to 49)
				icon_mod="critical"
			if(50 to INFINITY)
				icon_mod="on"
	if(icon_mod!=old_icon_mod)
		old_icon_mod=icon_mod
		update_icon()

	//spawn(40)
	//	stored_core_stability_delay = 0
	return


/obj/machinery/power/am_control_unit/interact(mob/user)
	if((get_dist(src, user) > 1) || (stat & (FORCEDISABLE|BROKEN|NOPOWER)))
		if(!istype(user, /mob/living/silicon/ai))
			user.unset_machine()
			user << browse(null, "window=AMcontrol")
			return
	return ui_interact(user)



/obj/machinery/power/am_control_unit/ui_interact(mob/user, ui_key = "main", var/datum/nanoui/ui = null, var/force_open=NANOUI_FOCUS)
	if(!user)
		return

	var/list/fueljar_data=null
	if(fueljar)
		fueljar_data=list(
			"fuel"=fueljar.fuel,
			"fuel_max"=fueljar.fuel_max,
			"injecting"=fuel_injection
		)

	var/list/data = list(
		"active" = active,
		//"stability" = stability,
		"linked_shields" = linked_shielding.len,
		"linked_cores" = linked_cores.len,
		"efficiency" = reported_core_efficiency,
		"stability" = stored_core_stability,
		"stored_power" = stored_power,
		"fueljar" = fueljar_data,
		"siliconUser" = istype(user, /mob/living/silicon),
	)

	ui = nanomanager.try_update_ui(user, src, ui_key, ui, data, force_open)
	if (!ui)
		// the ui does not exist, so we'll create a new one
		ui = new(user, src, ui_key, "ame.tmpl", "Antimatter Control Unit", 500, data["siliconUser"] ? 465 : 390)
		// When the UI is first opened this is the data it will use
		ui.set_initial_data(data)
		ui.open()
		// Auto update every Master Controller tick
		ui.set_auto_update(1)


/obj/machinery/power/am_control_unit/Topic(href, href_list)
	if(..())
		return 1
	if(href_list["close"])
		if(usr.machine == src)
			usr.unset_machine()
		return 1
	//Ignore input if we are broken or guy is not touching us, AI can control from a ways away
	if(stat & (BROKEN|NOPOWER|FORCEDISABLE))
		usr.unset_machine()
		usr << browse(null, "window=AMcontrol")
		return

	if(href_list["close"])
		usr << browse(null, "window=AMcontrol")
		usr.unset_machine()
		return

	if(href_list["togglestatus"])
		toggle_power()
		message_admins("AME toggled [active?"on":"off"] by [usr.real_name] ([usr.key]) at ([x],[y],[z] - <A HREF='?_src_=holder;adminplayerobservecoodjump=1;X=[x];Y=[y];Z=[z]'>JMP</a>)",0,1)

	if(href_list["refreshicons"])
		update_shield_icons = 2 // Fuck it

	if(href_list["ejectjar"])
		if(fueljar)
			message_admins("AME fuel jar ejected by [usr.real_name] ([usr.key]) at ([x],[y],[z] - <A HREF='?_src_=holder;adminplayerobservecoodjump=1;X=[x];Y=[y];Z=[z]'>JMP</a>)",0,1)
			fueljar.forceMove(src.loc)
			fueljar = null
			overlays.len = 0
			playsound(src, 'sound/machines/click.ogg', 50, 1)
			//fueljar.control_unit = null currently it does not care where it is
			//update_icon() when we have the icon for it

	if(href_list["set_strength"])
		var/newval = input("Enter new injection strength") as num|null
		if(isnull(newval))
			updateDialog()
			return
		fuel_injection=newval
		fuel_injection=max(1,fuel_injection)
		message_admins("AME injection strength set to [fuel_injection] by [usr.real_name] ([usr.key]) at ([x],[y],[z] - <A HREF='?_src_=holder;adminplayerobservecoodjump=1;X=[x];Y=[y];Z=[z]'>JMP</a>)",0,1)

	if(href_list["refreshstability"])
		check_core_stability()

	updateDialog()
	return 1

/obj/machinery/power/am_control_unit/npc_tamper_act(mob/living/L)
	if(prob(50)) //Toggle on/off
		toggle_power()
		message_admins("AME toggled [active?"on":"off"] by [key_name(L)] at [formatJumpTo(src)]",0,1)
	else //Set strength
		fuel_injection = rand(1, 300) //there's technically no limit on how high this can go so 300 is nothing but an arbitary limit
		message_admins("AME injection strength set to [fuel_injection] by [key_name(L)] at [formatJumpTo(src)]",0,1)
